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
module bindbc.newton.binddynamic;

import bindbc.loader;
import bindbc.newton.types;
import bindbc.newton.funcs;

enum NewtonSupport {
    noLibrary,
    badLibrary,
    newton314
}

private
{
    SharedLib lib;
    NewtonSupport loadedVersion;
}

void unloadNewton()
{
    if (lib != invalidHandle)
    {
        lib.unload();
    }
}

NewtonSupport loadedNewtonVersion() { return loadedVersion; }
bool isNewtonLoaded() { return lib != invalidHandle; }

NewtonSupport loadNewton()
{
    version(Windows)
    {
        const(char)[][1] libNames =
        [
            "newton.dll"
        ];
    }
    else version(OSX)
    {
        const(char)[][1] libNames =
        [
            "/usr/local/lib/libnewton.dylib"
        ];
    }
    else version(Posix)
    {
        const(char)[][1] libNames =
        [
            "libnewton.so"
        ];
    }
    else static assert(0, "bindbc-newton is not yet supported on this platform.");

    NewtonSupport ret;
    foreach(name; libNames)
    {
        ret = loadNewton(name.ptr);
        if (ret != NewtonSupport.noLibrary)
            break;
    }
    return ret;
}

NewtonSupport loadNewton(const(char)* libName)
{    
    lib = load(libName);
    if(lib == invalidHandle)
    {
        return NewtonSupport.noLibrary;
    }

    auto errCount = errorCount();
    loadedVersion = NewtonSupport.badLibrary;
    
    import std.algorithm.searching: startsWith;
    static foreach(m; __traits(allMembers, bindbc.newton.funcs))
    {
        static if (m.startsWith("da_"))
            lib.bindSymbol(
                cast(void**)&__traits(getMember, bindbc.newton.funcs, m[3..$]),
                __traits(getMember, bindbc.newton.funcs, m[3..$]).stringof);
    }
    
    loadedVersion = NewtonSupport.newton314;

    if (errorCount() != errCount)
        return NewtonSupport.badLibrary;

    return loadedVersion;
}
