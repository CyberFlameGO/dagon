/*
Copyright (c) 2019-2020 Timur Gafarov

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

module dagon.resource.image;

import std.stdio;
import std.path;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.core.stream;
import dlib.core.compound;
import dlib.image.image;
import dlib.image.io;
import dlib.image.unmanaged;
import dlib.image.hdri;
import dlib.filesystem.filesystem;

import dagon.graphics.containerimage;
import dagon.resource.asset;
version(USE_STBI) import dagon.resource.stbi;
import dagon.resource.dds;
import dagon.resource.texture;

class ImageAsset: Asset
{
    UnmanagedImageFactory imageFactory;
    UnmanagedHDRImageFactory hdrImageFactory;
    SuperImage image;

    this(UnmanagedImageFactory imgfac, UnmanagedHDRImageFactory hdrImgFac, Owner o)
    {
        super(o);
        imageFactory = imgfac;
        hdrImageFactory = hdrImgFac;
    }

    ~this()
    {
        release();
    }

    override bool loadThreadSafePart(string filename, InputStream istrm, ReadOnlyFileSystem fs, AssetManager mngr)
    {
        string errMsg;

        if (filename.extension == ".hdr" ||
            filename.extension == ".HDR")
        {
            Compound!(SuperHDRImage, string) res;
            ubyte[] data = New!(ubyte[])(istrm.size);
            istrm.fillArray(data);
            ArrayStream arrStrm = New!ArrayStream(data);
            res = loadHDR(arrStrm, hdrImageFactory);
            image = res[0];
            errMsg = res[1];
            Delete(arrStrm);
            Delete(data);
        }
        else if (filename.extension == ".dds" ||
                 filename.extension == ".DDS")
        {
            Compound!(ContainerImage, string) res;
            ubyte[] data = New!(ubyte[])(istrm.size);
            istrm.fillArray(data);
            ArrayStream arrStrm = New!ArrayStream(data);
            res = loadDDS(arrStrm);
            image = res[0];
            errMsg = res[1];
            Delete(arrStrm);
            Delete(data);
        }
        else
        {
            Compound!(SuperImage, string) res;
            
            version(USE_STBI)
            {
                switch(filename.extension)
                {
                    case ".bmp", ".BMP",
                         ".jpg", ".JPG", ".jpeg", ".JPEG",
                         ".png", ".PNG",
                         ".tga", ".TGA",
                         ".gif", ".GIF",
                         ".psd", ".PSD":
                        res = loadImageSTB(istrm, imageFactory);
                        break;
                    default:
                        return false;
                }
            }
            else
            {
                switch(filename.extension)
                {
                    case ".bmp", ".BMP":
                        res = loadImageDlib!loadBMP(istrm, imageFactory);
                        break;
                    case ".jpg", ".JPG", ".jpeg", ".JPEG":
                        res = loadImageDlib!loadJPEG(istrm, imageFactory);
                        break;
                    case ".png", ".PNG":
                        res = loadImageDlib!loadPNG(istrm, imageFactory);
                        break;
                    case ".tga", ".TGA":
                        res = loadImageDlib!loadTGA(istrm, imageFactory);
                        break;
                    default:
                        return false;
                }
            }

            image = res[0];
            errMsg = res[1];
        }

        if (image !is null)
        {
            return true;
        }
        else
        {
            writeln(errMsg);
            return false;
        }
    }

    override bool loadThreadUnsafePart()
    {
        if (image !is null)
            return true;
        else
            return false;
    }

    override void release()
    {
        if (image)
            Delete(image);
    }
}

ImageAsset imageAsset(AssetManager assetManager, string filename)
{
    ImageAsset asset;
    if (assetManager.assetExists(filename))
    {
        asset = cast(ImageAsset)assetManager.getAsset(filename);
    }
    else
    {
        asset = New!ImageAsset(assetManager.imageFactory, assetManager.hdrImageFactory, assetManager);
        assetManager.preloadAsset(asset, filename);
    }
    return asset;
}
