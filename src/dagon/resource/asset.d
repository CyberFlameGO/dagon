/*
Copyright (c) 2017-2022 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.resource.asset;

import std.stdio;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.core.compound;
import dlib.core.stream;
import dlib.core.thread;
import dlib.container.dict;
import dlib.filesystem.filesystem;
import dlib.filesystem.stdfs;
import dlib.image.image;
import dlib.image.unmanaged;
import dlib.image.hdri;
import dlib.image.io;

import dagon.core.event;
import dagon.core.vfs;
import dagon.resource.dds;
import dagon.resource.boxfs;

struct MonitorInfo
{
    FileStat lastStat;
    bool fileExists = false;
}

abstract class Asset: Owner
{
    this(Owner o)
    {
        super(o);
    }

    MonitorInfo monitorInfo;
    bool threadSafePartLoaded = false;
    bool threadUnsafePartLoaded = false;
    bool loadThreadSafePart(string filename, InputStream istrm, ReadOnlyFileSystem fs, AssetManager mngr);
    bool loadThreadUnsafePart();
    void release();
}

Compound!(SuperImage, string) dlibImageLoader(alias loadFunc)(InputStream istrm, SuperImageFactory imgFac)
{
    ubyte[] data = New!(ubyte[])(istrm.size);
    istrm.fillArray(data);
    ArrayStream arrStrm = New!ArrayStream(data);
    auto res = loadFunc(arrStrm, imgFac);
    Delete(arrStrm);
    Delete(data);
    return res;
}

alias ImageLoaderCallback = Compound!(SuperImage, string) function(InputStream, SuperImageFactory);

class AssetManager: Owner
{
    Dict!(ImageLoaderCallback, string) imageLoaderCallbacks;
    Dict!(Asset, string) assetsByFilename;
    VirtualFileSystem fs;
    StdFileSystem stdfs;
    UnmanagedImageFactory imageFactory;
    UnmanagedHDRImageFactory hdrImageFactory;
    Thread loadingThread;

    bool liveUpdate = false;
    double liveUpdatePeriod = 5.0;

    protected double monitorTimer = 0.0;

    float nextLoadingPercentage = 0.0f;

    EventManager eventManager;

    this(EventManager emngr, Owner o = null)
    {
        super(o);

        imageLoaderCallbacks = New!(Dict!(ImageLoaderCallback, string));
        registerImageLoader([".bmp", ".BMP"], &dlibImageLoader!loadBMP);
        registerImageLoader([".jpg", ".JPG", ".jpeg", ".JPEG"], &dlibImageLoader!loadJPEG);
        registerImageLoader([".png", ".PNG"], &dlibImageLoader!loadPNG);
        registerImageLoader([".tga", ".TGA"], &dlibImageLoader!loadTGA);
        
        assetsByFilename = New!(Dict!(Asset, string));
        fs = New!VirtualFileSystem();
        stdfs = New!StdFileSystem();
        fs.mount(stdfs);
        fs.mount(".");
        imageFactory = New!UnmanagedImageFactory();
        hdrImageFactory = New!UnmanagedHDRImageFactory();

        loadingThread = New!Thread(&threadFunc);

        eventManager = emngr;
    }

    ~this()
    {
        Delete(imageLoaderCallbacks);
        Delete(assetsByFilename);
        Delete(fs);
        Delete(imageFactory);
        Delete(hdrImageFactory);
        Delete(loadingThread);
    }

    void mountDirectory(string dir)
    {
        fs.mount(dir);
    }

    void mountBoxFile(string filename)
    {
        BoxFileSystem boxfs = New!BoxFileSystem(fs.openForInput(filename), true);
        fs.mount(boxfs);
    }

    void mountBoxFileDirectory(string filename, string dir)
    {
        BoxFileSystem boxfs = New!BoxFileSystem(fs.openForInput(filename), true, dir);
        fs.mount(boxfs);
    }
    
    void registerImageLoader(string extension, ImageLoaderCallback callback)
    {
        imageLoaderCallbacks[extension] = callback;
    }
    
    void registerImageLoader(string[] extensions, ImageLoaderCallback callback)
    {
        foreach(extension; extensions)
        {
            registerImageLoader(extension, callback);
        }
    }
    
    Compound!(SuperImage, string) loadImage(string extension, InputStream istrm)
    {
        if (extension == ".hdr" ||
            extension == ".HDR")
        {
            Compound!(SuperHDRImage, string) res;
            ubyte[] data = New!(ubyte[])(istrm.size);
            istrm.fillArray(data);
            ArrayStream arrStrm = New!ArrayStream(data);
            res = loadHDR(arrStrm, hdrImageFactory);
            SuperImage img = res[0];
            string errMsg = res[1];
            Delete(arrStrm);
            Delete(data);
            return compound(img, errMsg);
        }
        else if (extension in imageLoaderCallbacks)
        {
            return imageLoaderCallbacks[extension](istrm, imageFactory);
        }
        else
        {
            SuperImage img = null;
            return compound(img, "No loader registered for " ~ extension);
        }
    }

    bool assetExists(string name)
    {
        if (name in assetsByFilename)
            return true;
        else
            return false;
    }

    Asset addAsset(Asset asset, string name)
    {
        if (!(name in assetsByFilename))
        {
            assetsByFilename[name] = asset;
            if (fs.stat(name, asset.monitorInfo.lastStat))
                asset.monitorInfo.fileExists = true;
        }
        return asset;
    }

    Asset preloadAsset(Asset asset, string name)
    {
        if (!(name in assetsByFilename))
        {
            assetsByFilename[name] = asset;
            if (fs.stat(name, asset.monitorInfo.lastStat))
                asset.monitorInfo.fileExists = true;
        }

        asset.release();
        asset.threadSafePartLoaded = false;
        asset.threadUnsafePartLoaded = false;

        asset.threadSafePartLoaded = loadAssetThreadSafePart(asset, name);
        if (asset.threadSafePartLoaded)
            asset.threadUnsafePartLoaded = asset.loadThreadUnsafePart();

        return asset;
    }

    void reloadAsset(Asset asset, string filename)
    {
        asset.release();
        asset.threadSafePartLoaded = false;
        asset.threadUnsafePartLoaded = false;

        asset.threadSafePartLoaded = loadAssetThreadSafePart(asset, filename);
        if (asset.threadSafePartLoaded)
            asset.threadUnsafePartLoaded = asset.loadThreadUnsafePart();
    }

    void reloadAsset(string name)
    {
        auto asset = assetsByFilename[name];

        asset.release();
        asset.threadSafePartLoaded = false;
        asset.threadUnsafePartLoaded = false;

        asset.threadSafePartLoaded = loadAssetThreadSafePart(asset, name);
        if (asset.threadSafePartLoaded)
            asset.threadUnsafePartLoaded = asset.loadThreadUnsafePart();
    }

    Asset getAsset(string name)
    {
        if (name in assetsByFilename)
            return assetsByFilename[name];
        else
            return null;
    }

    void removeAsset(string name)
    {
        Delete(assetsByFilename[name]);
        assetsByFilename.remove(name);
    }

    void releaseAssets()
    {
        clearOwnedObjects();
        Delete(assetsByFilename);
        assetsByFilename = New!(Dict!(Asset, string));

        Delete(loadingThread);
        loadingThread = New!Thread(&threadFunc);
    }
    
    bool loadAssetThreadSafePart(Asset asset, ubyte[] buffer, string filename)
    {
        ArrayStream arrStrm = New!ArrayStream(buffer);
        bool res = loadAssetThreadSafePart(asset, arrStrm, filename);
        Delete(arrStrm);
        return res;
    }
    
    bool loadAssetThreadSafePart(Asset asset, InputStream istrm, string filename)
    {
        bool res = asset.loadThreadSafePart(filename, istrm, fs, this);
        if (!res)
        {
            writefln("Error: failed to load asset \"%s\"", filename);
        }
        return res;
    }

    bool loadAssetThreadSafePart(Asset asset, string filename)
    {
        if (!fileExists(filename))
        {
            writefln("Error: cannot find file \"%s\"", filename);
            return false;
        }

        auto fstrm = fs.openForInput(filename);
        bool res = loadAssetThreadSafePart(asset, fstrm, filename);
        Delete(fstrm);
        return res;
    }

    void threadFunc()
    {
        foreach(filename, asset; assetsByFilename)
        {
            nextLoadingPercentage += 1.0f / cast(float)(assetsByFilename.length);

            if (!asset.threadSafePartLoaded)
            {
                asset.threadSafePartLoaded = loadAssetThreadSafePart(asset, filename);
                asset.threadUnsafePartLoaded = false;
            }
        }
    }

    void loadThreadSafePart()
    {
        nextLoadingPercentage = 0.0f;
        monitorTimer = 0.0;
        loadingThread.start();
    }

    bool isLoading()
    {
        return loadingThread.isRunning;
    }

    bool loadThreadUnsafePart()
    {
        bool res = true;
        foreach(filename, asset; assetsByFilename)
        //if (!asset.threadUnsafePartLoaded)
        if (asset.threadSafePartLoaded)
        {
            res = asset.loadThreadUnsafePart();
            asset.threadUnsafePartLoaded = res;
            if (!res)
            {
                writefln("Error: failed to load asset \"%s\"", filename);
                break;
            }
        }
        else
        {
            res = false;
            break;
        }
        return res;
    }

    bool fileExists(string filename)
    {
        FileStat stat;
        return fs.stat(filename, stat);
    }

    void updateMonitor(double dt)
    {
        if (liveUpdate)
        {
            monitorTimer += dt;
            if (monitorTimer >= liveUpdatePeriod)
            {
                monitorTimer = 0.0;
                foreach(filename, asset; assetsByFilename)
                    monitorCheck(filename, asset);
            }
        }
    }

    protected void monitorCheck(string filename, Asset asset)
    {
        FileStat currentStat;
        if (fs.stat(filename, currentStat))
        {
            if (!asset.monitorInfo.fileExists)
            {
                asset.monitorInfo.fileExists = true;
            }
            else if (currentStat.modificationTimestamp >
                     asset.monitorInfo.lastStat.modificationTimestamp ||
                     currentStat.sizeInBytes !=
                     asset.monitorInfo.lastStat.sizeInBytes)
            {
                reloadAsset(filename);
                asset.monitorInfo.lastStat = currentStat;
                eventManager.generateFileChangeEvent(filename);
            }
        }
        else
        {
            if (asset.monitorInfo.fileExists)
            {
                asset.monitorInfo.fileExists = false;
            }
        }
    }
}
