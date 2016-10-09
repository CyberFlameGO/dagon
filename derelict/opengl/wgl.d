/*

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
module derelict.opengl.wgl;

private
{
    import derelict.util.wintypes;
    import derelict.util.compat;
}

version(Windows)
{
    extern(Windows)
    {
        alias BOOL function(void*,void*) da_wglCopyContext;
        alias void* function(void*) da_wglCreateContext;
        alias void* function(void*,int) da_wglCreateLayerContext;
        alias BOOL function(void*) da_wglDeleteContext;
        alias BOOL function(void*,int,int,UINT,LAYERPLANEDESCRIPTOR*) da_wglDescribeLayerPlane;
        alias void* function() da_wglGetCurrentContext;
        alias void* function() da_wglGetCurrentDC;
        alias int function(void*,int,int,int,COLORREF*) da_wglGetLayerPaletteEntries;
        alias FARPROC function(LPCSTR) da_wglGetProcAddress;
        alias BOOL function(void*,void*) da_wglMakeCurrent;
        alias BOOL function(void*,int,BOOL) da_wglRealizeLayerPalette;
        alias int function(void*,int,int,int,COLORREF*) da_wglSetLayerPaletteEntries;
        alias BOOL function(void*,void*) da_wglShareLists;
        alias BOOL function(void*,UINT) da_wglSwapLayerBuffers;
        alias BOOL function(void*,DWORD,DWORD,DWORD) da_wglUseFontBitmapsA;
        alias BOOL function(void*,DWORD,DWORD,DWORD,FLOAT,FLOAT,int,GLYPHMETRICSFLOAT*) da_wglUseFontOutlinesA;
        alias BOOL function(void*,DWORD,DWORD,DWORD) da_wglUseFontBitmapsW;
        alias BOOL function(void*,DWORD,DWORD,DWORD,FLOAT,FLOAT,int,GLYPHMETRICSFLOAT*) da_wglUseFontOutlinesW;

    }

    mixin(gsharedString!() ~
    "
    da_wglCopyContext wglCopyContext;
    da_wglCreateContext wglCreateContext;
    da_wglCreateLayerContext wglCreateLayerContext;
    da_wglDeleteContext wglDeleteContext;
    da_wglDescribeLayerPlane wglDescribeLayerPlane;
    da_wglGetCurrentContext wglGetCurrentContext;
    da_wglGetCurrentDC wglGetCurrentDC;
    da_wglGetLayerPaletteEntries wglGetLayerPaletteEntries;
    da_wglGetProcAddress wglGetProcAddress;
    da_wglMakeCurrent wglMakeCurrent;
    da_wglRealizeLayerPalette wglRealizeLayerPalette;
    da_wglSetLayerPaletteEntries wglSetLayerPaletteEntries;
    da_wglShareLists wglShareLists;
    da_wglSwapLayerBuffers wglSwapLayerBuffers;
    da_wglUseFontBitmapsA wglUseFontBitmapsA;
    da_wglUseFontOutlinesA wglUseFontOutlinesA;
    da_wglUseFontBitmapsW wglUseFontBitmapsW;
    da_wglUseFontOutlinesW wglUseFontOutlinesW;

    alias wglUseFontBitmapsA    wglUseFontBitmaps;
    alias wglUseFontOutlinesA   wglUseFontOutlines;
    ");


    package
    {
        void loadPlatformGL(void delegate(void**, string, bool doThrow = true) bindFunc)
        {
            bindFunc(cast(void**)&wglCopyContext, "wglCopyContext", false);
            bindFunc(cast(void**)&wglCreateContext, "wglCreateContext", false);
            bindFunc(cast(void**)&wglCreateLayerContext, "wglCreateLayerContext", false);
            bindFunc(cast(void**)&wglDeleteContext, "wglDeleteContext", false);
            bindFunc(cast(void**)&wglDescribeLayerPlane, "wglDescribeLayerPlane", false);
            bindFunc(cast(void**)&wglGetCurrentContext, "wglGetCurrentContext", false);
            bindFunc(cast(void**)&wglGetCurrentDC, "wglGetCurrentDC", false);
            bindFunc(cast(void**)&wglGetLayerPaletteEntries, "wglGetLayerPaletteEntries", false);
            bindFunc(cast(void**)&wglGetProcAddress, "wglGetProcAddress", false);
            bindFunc(cast(void**)&wglMakeCurrent, "wglMakeCurrent", false);
            bindFunc(cast(void**)&wglRealizeLayerPalette, "wglRealizeLayerPalette", false);
            bindFunc(cast(void**)&wglSetLayerPaletteEntries, "wglSetLayerPaletteEntries", false);
            bindFunc(cast(void**)&wglShareLists, "wglShareLists", false);
            bindFunc(cast(void**)&wglSwapLayerBuffers, "wglSwapLayerBuffers", false);
            bindFunc(cast(void**)&wglUseFontBitmapsA, "wglUseFontBitmapsA", false);
            bindFunc(cast(void**)&wglUseFontOutlinesA, "wglUseFontOutlinesA", false);
            bindFunc(cast(void**)&wglUseFontBitmapsW, "wglUseFontBitmapsW", false);
            bindFunc(cast(void**)&wglUseFontOutlinesW, "wglUseFontOutlinesW", false);
        }

        void* loadGLSymbol(string symName)
        {
            return cast(void*)wglGetProcAddress(toCString(symName));
        }
    }
}