/*
Copyright (c) 2021 Timur Gafarov

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
module dagon.resource.gltf;

import std.stdio;
import std.path;
import std.algorithm;
import std.base64;
import dlib.core.memory;
import dlib.core.ownership;
import dlib.core.stream;
import dlib.filesystem.filesystem;
import dlib.container.array;
import dlib.serialization.json;
import dlib.text.str;
import dlib.math.vector;
import dlib.image.image;

import dagon.core.bindings;
import dagon.resource.asset;
import dagon.resource.texture;
import dagon.graphics.drawable;
import dagon.graphics.mesh;
import dagon.graphics.texture;
import dagon.graphics.material;

class GLTFBuffer: Owner
{
    ubyte[] array;
    
    this(Owner o)
    {
        super(o);
    }
    
    void fromArray(ubyte[] arr)
    {
        array = New!(ubyte[])(arr.length);
        array[] = arr[];
    }
    
    void fromStream(InputStream istrm)
    {
        if (istrm is null)
            return;
        
        array = New!(ubyte[])(istrm.size);
        if (!istrm.fillArray(array))
        {
            writeln("Warning: failed to read buffer");
            Delete(array);
        }
    }
    
    void fromFile(ReadOnlyFileSystem fs, string filename)
    {
        FileStat fstat;
        if (fs.stat(filename, fstat))
        {
            auto bufStream = fs.openForInput(filename);
            fromStream(bufStream);
            Delete(bufStream);
        }
        else
            writeln("Warning: buffer file \"", filename, "\" not found");
    }
    
    void fromBase64(string encoded)
    {
        auto decodedLength = Base64.decodeLength(encoded.length);
        array = New!(ubyte[])(decodedLength);
        auto decoded = Base64.decode(encoded, array);
    }
    
    ~this()
    {
        if (array.length)
            Delete(array);
    }
}

class GLTFBufferView: Owner
{
    GLTFBuffer buffer;
    uint offset;
    uint len;
    uint stride;
    ubyte[] slice;
    GLenum target;
    
    this(GLTFBuffer buffer, uint offset, uint len, uint stride, GLenum target, Owner o)
    {
        super(o);
        
        if (buffer is null)
            return;
        
        this.buffer = buffer;
        this.offset = offset;
        this.len = len;
        this.stride = stride;
        this.target = target;
        
        if (offset < buffer.array.length && offset+len <= buffer.array.length)
        {
            this.slice = buffer.array[offset..offset+len];
        }
        else
        {
            writeln("Warning: invalid buffer view bounds");
        }
    }
    
    ~this()
    {
    }
}

enum GLTFDataType
{
    Undefined,
    Scalar,
    Vec2,
    Vec3,
    Vec4,
    Mat2,
    Mat3,
    Mat4
}

class GLTFAccessor: Owner
{
    GLTFBufferView bufferView;
    GLTFDataType dataType;
    uint numComponents;
    GLenum componentType;
    uint count;
    uint byteOffset;
    
    this(GLTFBufferView bufferView, GLTFDataType dataType, GLenum componentType, uint count, uint byteOffset, Owner o)
    {
        super(o);
        
        if (bufferView is null)
            return;
        
        this.bufferView = bufferView;
        this.dataType = dataType;
        this.componentType = componentType;
        this.count = count;
        this.byteOffset = byteOffset;
        
        switch(dataType)
        {
            case GLTFDataType.Scalar: numComponents = 1; break;
            case GLTFDataType.Vec2:   numComponents = 2; break;
            case GLTFDataType.Vec3:   numComponents = 3; break;
            case GLTFDataType.Vec4:   numComponents = 4; break;
            case GLTFDataType.Mat2:   numComponents = 2 * 2; break;
            case GLTFDataType.Mat3:   numComponents = 3 * 3; break;
            case GLTFDataType.Mat4:   numComponents = 4 * 4; break;
            default: numComponents = 1; break;
        }
    }
    
    ~this()
    {
    }
}

class GLTFMesh: Owner, Drawable
{
    GLTFAccessor positionAccessor;
    GLTFAccessor normalAccessor;
    GLTFAccessor texCoord0Accessor;
    GLTFAccessor indexAccessor;
    Material material;
    
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint nbo = 0;
    GLuint tbo = 0;
    GLuint eao = 0;
    
    bool canRender = false;
    
    this(GLTFAccessor positionAccessor, GLTFAccessor normalAccessor, GLTFAccessor texCoord0Accessor, GLTFAccessor indexAccessor, Material material, Owner o)
    {
        super(o);
        this.positionAccessor = positionAccessor;
        this.normalAccessor = normalAccessor;
        this.texCoord0Accessor = texCoord0Accessor;
        this.indexAccessor = indexAccessor;
        this.material = material;
    }
    
    void prepareVAO()
    {
        if (positionAccessor is null || 
            normalAccessor is null || 
            texCoord0Accessor is null || 
            indexAccessor is null)
            return;
        
        if (positionAccessor.bufferView.slice.length == 0)
            return;
        if (normalAccessor.bufferView.slice.length == 0)
            return;
        if (texCoord0Accessor.bufferView.slice.length == 0)
            return;
        if (indexAccessor.bufferView.slice.length == 0)
            return;
        
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, positionAccessor.bufferView.slice.length, positionAccessor.bufferView.slice.ptr, GL_STATIC_DRAW); 
        
        glGenBuffers(1, &nbo);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glBufferData(GL_ARRAY_BUFFER, normalAccessor.bufferView.slice.length, normalAccessor.bufferView.slice.ptr, GL_STATIC_DRAW);
        
        glGenBuffers(1, &tbo);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glBufferData(GL_ARRAY_BUFFER, texCoord0Accessor.bufferView.slice.length, texCoord0Accessor.bufferView.slice.ptr, GL_STATIC_DRAW);
        
        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indexAccessor.bufferView.slice.length, indexAccessor.bufferView.slice.ptr, GL_STATIC_DRAW);
        
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        
        glEnableVertexAttribArray(VertexAttrib.Vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(VertexAttrib.Vertices, positionAccessor.numComponents, positionAccessor.componentType, GL_FALSE, positionAccessor.bufferView.stride, cast(void*)positionAccessor.byteOffset);
        
        glEnableVertexAttribArray(VertexAttrib.Normals);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glVertexAttribPointer(VertexAttrib.Normals, normalAccessor.numComponents, normalAccessor.componentType, GL_FALSE, normalAccessor.bufferView.stride, cast(void*)normalAccessor.byteOffset);
        
        glEnableVertexAttribArray(VertexAttrib.Texcoords);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glVertexAttribPointer(VertexAttrib.Texcoords, texCoord0Accessor.numComponents, texCoord0Accessor.componentType, GL_FALSE, texCoord0Accessor.bufferView.stride, cast(void*)texCoord0Accessor.byteOffset);
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        
        glBindVertexArray(0);
        
        canRender = true;
    }
    
    void render(GraphicsState* state)
    {
        if (canRender)
        {
            glBindVertexArray(vao);
            glDrawElements(GL_TRIANGLES, indexAccessor.count, indexAccessor.componentType, cast(void*)indexAccessor.byteOffset);
            glBindVertexArray(0);
        }
    }
    
    ~this()
    {
        if (canRender)
        {
            glDeleteVertexArrays(1, &vao);
            glDeleteBuffers(1, &vbo);
            glDeleteBuffers(1, &nbo);
            glDeleteBuffers(1, &tbo);
            glDeleteBuffers(1, &eao);
        }
    }
}

class GLTFAsset: Asset
{
    AssetManager assetManager;
    String str;
    JSONDocument doc;
    Array!GLTFBuffer buffers;
    Array!GLTFBufferView bufferViews;
    Array!GLTFAccessor accessors;
    Array!GLTFMesh meshes;
    Array!TextureAsset images;
    Array!Texture textures;
    Array!Material materials;
    
    this(Owner o)
    {
        super(o);
    }
    
    ~this()
    {
        release();
    }
    
    override bool loadThreadSafePart(string filename, InputStream istrm, ReadOnlyFileSystem fs, AssetManager mngr)
    {
        assetManager = mngr;
        string rootDir = dirName(filename);
        str = String(istrm);
        doc = New!JSONDocument(str.toString);
        loadBuffers(doc.root, fs, rootDir);
        loadBufferViews(doc.root);
        loadAccessors(doc.root);
        loadImages(doc.root, fs, rootDir);
        loadTextures(doc.root);
        loadMaterials(doc.root);
        loadMeshes(doc.root);
        return true;
    }
    
    void loadBuffers(JSONValue root, ReadOnlyFileSystem fs, string rootDir)
    {
        if ("buffers" in root.asObject)
        {
            foreach(buffer; root.asObject["buffers"].asArray)
            {
                auto buf = buffer.asObject;
                if ("uri" in buf)
                {
                    string uri = buf["uri"].asString;
                    string base64Prefix = "data:application/octet-stream;base64,";
                    
                    GLTFBuffer b = New!GLTFBuffer(this);
                    
                    if (uri.startsWith(base64Prefix))
                    {
                        auto encoded = uri[base64Prefix.length..$];
                        b.fromBase64(encoded);
                    }
                    else
                    {
                        String bufFilename = String(rootDir);
                        bufFilename ~= "/";
                        bufFilename ~= buf["uri"].asString;
                        b.fromFile(fs, bufFilename.toString);
                        bufFilename.free();
                    }
                    
                    buffers.insertBack(b);
                }
            }
        }
    }
    
    void loadBufferViews(JSONValue root)
    {
        if ("bufferViews" in root.asObject)
        {
            foreach(bufferView; root.asObject["bufferViews"].asArray)
            {
                auto bv = bufferView.asObject;
                uint bufferIndex = 0;
                uint byteOffset = 0;
                uint byteLength = 0;
                uint byteStride = 0;
                GLenum target = GL_ARRAY_BUFFER;
                
                if ("buffer" in bv)
                    bufferIndex = cast(uint)bv["buffer"].asNumber;
                if ("byteOffset" in bv)
                    byteOffset = cast(uint)bv["byteOffset"].asNumber;
                if ("byteLength" in bv)
                    byteLength = cast(uint)bv["byteLength"].asNumber;
                if ("byteStride" in bv)
                    byteStride = cast(uint)bv["byteStride"].asNumber;
                if ("target" in bv)
                    target = cast(GLenum)bv["target"].asNumber;
                
                if (bufferIndex < buffers.length)
                {
                    GLTFBufferView bufv = New!GLTFBufferView(buffers[bufferIndex], byteOffset, byteLength, byteStride, target, this);
                    bufferViews.insertBack(bufv);
                }
                else
                {
                    writeln("Warning: can't create buffer view for nonexistent buffer ", bufferIndex);
                    GLTFBufferView bufv = New!GLTFBufferView(null, 0, 0, 0, 0, this);
                    bufferViews.insertBack(bufv);
                }
            }
        }
    }
    
    void loadAccessors(JSONValue root)
    {
        if ("accessors" in root.asObject)
        {
            foreach(i, accessor; root.asObject["accessors"].asArray)
            {
                auto acc = accessor.asObject;
                uint bufferViewIndex = 0;
                GLenum componentType = GL_FLOAT;
                string type;
                uint count = 0;
                uint byteOffset = 0;
                
                if ("bufferView" in acc)
                    bufferViewIndex = cast(uint)acc["bufferView"].asNumber;
                if ("componentType" in acc)
                    componentType = cast(GLenum)acc["componentType"].asNumber;
                if ("type" in acc)
                    type = acc["type"].asString;
                if ("count" in acc)
                    count = cast(uint)acc["count"].asNumber;
                if ("byteOffset" in acc)
                    byteOffset = cast(uint)acc["byteOffset"].asNumber;
                
                GLTFDataType dataType = GLTFDataType.Undefined;
                if (type == "SCALAR")
                    dataType = GLTFDataType.Scalar;
                else if (type == "VEC2")
                    dataType = GLTFDataType.Vec2;
                else if (type == "VEC3")
                    dataType = GLTFDataType.Vec3;
                else if (type == "VEC4")
                    dataType = GLTFDataType.Vec4;
                else if (type == "MAT2")
                    dataType = GLTFDataType.Mat2;
                else if (type == "MAT3")
                    dataType = GLTFDataType.Mat3;
                else if (type == "MAT4")
                    dataType = GLTFDataType.Mat4;
                else
                    writeln("Warning: unsupported data type for accessor ", i);
                
                if (bufferViewIndex < bufferViews.length)
                {
                    GLTFAccessor ac = New!GLTFAccessor(bufferViews[bufferViewIndex], dataType, componentType, count, byteOffset, this);
                    accessors.insertBack(ac);
                }
                else
                {
                    writeln("Warning: can't create accessor for nonexistent buffer view ", bufferViewIndex);
                    GLTFAccessor ac = New!GLTFAccessor(null, dataType, componentType, count, byteOffset, this);
                    accessors.insertBack(ac);
                }
            }
        }
    }
    
    void loadImages(JSONValue root, ReadOnlyFileSystem fs, string rootDir)
    {
        if ("images" in root.asObject)
        {
            foreach(i, img; root.asObject["images"].asArray)
            {
                auto im = img.asObject;
                
                if ("uri" in im)
                {
                    String imgFilename = String(rootDir);
                    imgFilename ~= "/";
                    imgFilename ~= im["uri"].asString;
                    
                    auto ta = New!TextureAsset(assetManager.imageFactory, assetManager.hdrImageFactory, this);
                    
                    FileStat fstat;
                    if (fs.stat(imgFilename.toString, fstat))
                    {
                        bool res = assetManager.loadAssetThreadSafePart(ta, imgFilename.toString);
                        if (!res)
                            writeln("Warning: failed to load \"", imgFilename, "\" not found");
                    }
                    else
                    {
                        writeln("Warning: image file \"", imgFilename, "\" not found");
                    }
                    
                    images.insertBack(ta);
                    
                    imgFilename.free();
                }
                else if ("bufferView" in im)
                {
                    uint bufferViewIndex = cast(uint)im["bufferView"].asNumber;
                    
                    auto ta = New!TextureAsset(assetManager.imageFactory, assetManager.hdrImageFactory, this);
                    
                    if (bufferViewIndex < bufferViews.length)
                    {
                        auto bv = bufferViews[bufferViewIndex];
                        string mimeType = "";
                        if ("mimeType" in im)
                            mimeType = im["mimeType"].asString;
                        if (mimeType == "")
                            writeln("Warning: image MIME type missing");
                        else
                        {
                            string name = nameFromMimeType(mimeType);
                            if (name == "")
                            {
                                writeln("Warning: unsupported image MIME type ", mimeType);
                            }
                            else
                            {
                                
                                bool res = assetManager.loadAssetThreadSafePart(ta, bv.slice, name);
                                if (!res)
                                    writeln("Warning: failed to load image");
                            }
                        }
                    }
                    else
                    {
                        writeln("Warning: can't create image from nonexistent buffer view ", bufferViewIndex);
                    }
                    
                    images.insertBack(ta);
                }
            }
        }
    }
    
    // TODO: loadSamplers
    
    void loadTextures(JSONValue root)
    {
        if ("textures" in root.asObject)
        {
            foreach(i, tex; root.asObject["textures"].asArray)
            {
                auto te = tex.asObject;
                
                if ("source" in te)
                {
                    uint imageIndex = cast(uint)te["source"].asNumber;
                    TextureAsset img;
                    if (imageIndex < images.length)
                        img = images[imageIndex];
                    else
                        writeln("Warning: can't create texture for nonexistent image ", imageIndex);
                    
                    if (img !is null)
                    {
                        Texture texture = img.texture;
                        textures.insertBack(texture);
                    }
                    else
                    {
                        Texture texture;
                        textures.insertBack(texture);
                    }
                }
                
                // TODO: sampler
            }
        }
    }
    
    void loadMaterials(JSONValue root)
    {
        if ("materials" in root.asObject)
        {
            foreach(i, mat; root.asObject["materials"].asArray)
            {
                auto ma = mat.asObject;
                
                Material material = New!Material(this);
                
                if ("pbrMetallicRoughness" in ma)
                {
                    auto pbr = ma["pbrMetallicRoughness"].asObject;
                    
                    if (pbr && "baseColorTexture" in pbr)
                    {
                        auto bct = pbr["baseColorTexture"].asObject;
                        if ("index" in bct)
                        {
                            uint baseColorTexIndex = cast(uint)bct["index"].asNumber;
                            if (baseColorTexIndex < textures.length)
                            {
                                Texture baseColorTex = textures[baseColorTexIndex];
                                if (baseColorTex)
                                {
                                    material.diffuse = baseColorTex;
                                    if (baseColorTex.image.pixelFormat == IntegerPixelFormat.RGBA8)
                                        material.blending = Transparent;
                                }
                            }
                        }
                    }
                    
                    if (pbr && "metallicRoughnessTexture" in pbr)
                    {
                        uint metallicRoughnessTexIndex = cast(uint)pbr["metallicRoughnessTexture"].asObject["index"].asNumber;
                        if (metallicRoughnessTexIndex < textures.length)
                        {
                            Texture metallicRoughnessTex = textures[metallicRoughnessTexIndex];
                            if (metallicRoughnessTex)
                                material.roughnessMetallic = metallicRoughnessTex;
                        }
                    }
                    
                    if (pbr && "metallicFactor" in pbr)
                    {
                        material.metallic = pbr["metallicFactor"].asNumber;
                    }
                    
                    if (pbr && "roughnessFactor" in pbr)
                    {
                        material.roughness = pbr["roughnessFactor"].asNumber;
                    }
                }
                else if ("extensions" in ma)
                {
                    auto extensions = ma["extensions"].asObject;
                    
                    if ("KHR_materials_pbrSpecularGlossiness" in extensions)
                    {
                        auto pbr = extensions["KHR_materials_pbrSpecularGlossiness"].asObject;
                        
                        if (pbr && "diffuseTexture" in pbr)
                        {
                            auto dt = pbr["diffuseTexture"].asObject;
                            if ("index" in dt)
                            {
                                uint diffuseTexIndex = cast(uint)dt["index"].asNumber;
                                if (diffuseTexIndex < textures.length)
                                {
                                    Texture diffuseTex = textures[diffuseTexIndex];
                                    if (diffuseTex)
                                    {
                                        material.diffuse = diffuseTex;
                                        if (diffuseTex.image.pixelFormat == IntegerPixelFormat.RGBA8)
                                            material.blending = Transparent;
                                    }
                                }
                            }
                        }
                    }
                }
                
                if ("normalTexture" in ma)
                {
                    uint normalTexIndex = cast(uint)ma["normalTexture"].asObject["index"].asNumber;
                    if (normalTexIndex < textures.length)
                    {
                        Texture normalTex = textures[normalTexIndex];
                        if (normalTex)
                            material.normal = normalTex;
                    }
                }
                
                if ("emissiveTexture" in ma)
                {
                    uint emissiveTexIndex = cast(uint)ma["emissiveTexture"].asObject["index"].asNumber;
                    if (emissiveTexIndex < textures.length)
                    {
                        Texture emissiveTex = textures[emissiveTexIndex];
                        if (emissiveTex)
                            material.emission = emissiveTex;
                    }
                }
                
                materials.insertBack(material);
            }
        }
    }
    
    void loadMeshes(JSONValue root)
    {
        if ("meshes" in root.asObject)
        {
            foreach(i, mesh; root.asObject["meshes"].asArray)
            {
                auto m = mesh.asObject;
                
                if ("primitives" in m)
                {
                    foreach(prim; m["primitives"].asArray)
                    {
                        auto p = prim.asObject;
                        
                        GLTFAccessor positionAccessor;
                        GLTFAccessor normalAccessor;
                        GLTFAccessor texCoord0Accessor;
                        GLTFAccessor indexAccessor;
                        
                        if ("attributes" in p)
                        {
                            auto attributes = p["attributes"].asObject;
                            
                            if ("POSITION" in attributes)
                            {
                                uint positionsAccessorIndex = cast(uint)attributes["POSITION"].asNumber;
                                if (positionsAccessorIndex < accessors.length)
                                    positionAccessor = accessors[positionsAccessorIndex];
                                else
                                    writeln("Warning: can't create position attributes for nonexistent accessor ", positionsAccessorIndex);
                            }
                            
                            if ("NORMAL" in attributes)
                            {
                                uint normalsAccessorIndex = cast(uint)attributes["NORMAL"].asNumber;
                                if (normalsAccessorIndex < accessors.length)
                                    normalAccessor = accessors[normalsAccessorIndex];
                                else
                                    writeln("Warning: can't create normal attributes for nonexistent accessor ", normalsAccessorIndex);
                            }
                            
                            if ("TEXCOORD_0" in attributes)
                            {
                                uint texCoord0AccessorIndex = cast(uint)attributes["TEXCOORD_0"].asNumber;
                                if (texCoord0AccessorIndex < accessors.length)
                                    texCoord0Accessor = accessors[texCoord0AccessorIndex];
                                else
                                    writeln("Warning: can't create texCoord0 attributes for nonexistent accessor ", texCoord0AccessorIndex);
                            }
                        }
                        
                        if ("indices" in p)
                        {
                            uint indicesAccessorIndex = cast(uint)p["indices"].asNumber;
                            if (indicesAccessorIndex < accessors.length)
                                indexAccessor = accessors[indicesAccessorIndex];
                            else
                                writeln("Warning: can't create indices for nonexistent accessor ", indicesAccessorIndex);
                        }
                        
                        Material material;
                        if ("material" in p)
                        {
                            uint materialIndex = cast(uint)p["material"].asNumber;
                            if (materialIndex < materials.length)
                                material = materials[materialIndex];
                            else
                                writeln("Warning: nonexistent material ", materialIndex);
                        }
                        
                        if (positionAccessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks vertex position attributes");
                            //continue;
                        }
                        if (normalAccessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks vertex normal attributes");
                            //continue;
                        }
                        if (texCoord0Accessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks vertex texCoord0 attributes");
                            //continue;
                        }
                        if (indexAccessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks indices");
                            //continue;
                        }
                        
                        GLTFMesh me = New!GLTFMesh(positionAccessor, normalAccessor, texCoord0Accessor, indexAccessor, material, this);
                        meshes.insertBack(me);
                    }
                }
            }
        }
    }
    
    override bool loadThreadUnsafePart()
    {
        foreach(me; meshes)
        {
            me.prepareVAO();
        }
        
        foreach(img; images)
        {
            img.loadThreadUnsafePart();
        }
        
        return true;
    }
    
    override void release()
    {
        foreach(b; buffers)
            deleteOwnedObject(b);
        buffers.free();
        
        foreach(bv; bufferViews)
            deleteOwnedObject(bv);
        bufferViews.free();
        
        foreach(ac; accessors)
            deleteOwnedObject(ac);
        accessors.free();
        
        foreach(me; meshes)
            deleteOwnedObject(me);
        meshes.free();
        
        foreach(im; images)
            deleteOwnedObject(im);
        images.free();
        
        textures.free();
        
        materials.free();
        
        Delete(doc);
        str.free();
    }
}

string nameFromMimeType(string mime)
{
    string name;
    switch(mime)
    {
        case "image/jpeg": name = "undefined.jpg"; break;
        case "image/png": name = "undefined.png"; break;
        case "image/tga": name = "undefined.tga"; break;
        case "image/targa": name = "undefined.tga"; break;
        case "image/bmp": name = "undefined.bmp"; break;
        case "image/vnd.radiance": name = "undefined.hdr"; break;
        case "image/x-hdr": name = "undefined.hdr"; break;
        case "image/x-dds": name = "undefined.dds"; break;
        default: name = ""; break;
    }
    return name;
}
