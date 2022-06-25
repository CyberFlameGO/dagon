/*
Copyright (c) 2019-2022 Timur Gafarov

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

module dagon.game.deferredrenderer;

import dlib.core.memory;
import dlib.core.ownership;

import dagon.core.event;
import dagon.core.time;
import dagon.resource.scene;
import dagon.render.passes;
import dagon.render.gbuffer;
import dagon.render.view;
import dagon.render.framebuffer;
import dagon.postproc.filterpass;
import dagon.postproc.shaders.denoise;
import dagon.game.renderer;

class DeferredRenderer: Renderer
{
    GBuffer gbuffer;
    PassShadow passShadow;
    PassBackground passBackground;
    PassTerrain passTerrain;
    PassGeometry passStaticGeometry;
    PassDecal passDecal;
    PassGeometry passDynamicGeometry;
    PassOcclusion passOcclusion;
    FilterPass passOcclusionDenoise;
    PassEnvironment passEnvironment;
    PassLight passLight;
    PassForward passForward;
    PassParticles passParticles;
    
    Framebuffer terrainNormalBuffer;
    Framebuffer terrainTexcoordBuffer;
    
    DenoiseShader denoiseShader;
    RenderView occlusionView;
    Framebuffer occlusionNoisyBuffer;
    Framebuffer occlusionBuffer;
    bool _ssaoEnabled = true;
    float _occlusionBufferDetail = 1.0f;
    int ssaoSamples = 20;
    float ssaoRadius = 0.2f;
    float ssaoPower = 5.0f;
    float ssaoDenoise = 1.0f;
    
    void ssaoEnabled(bool mode) @property
    {
        _ssaoEnabled = mode;
        passOcclusion.active = mode;
        passOcclusionDenoise.active = mode;
        if (_ssaoEnabled)
        {
            passEnvironment.occlusionBuffer = occlusionBuffer;
            passLight.occlusionBuffer = occlusionBuffer;
        }
        else
        {
            passEnvironment.occlusionBuffer = null;
            passLight.occlusionBuffer = null;
        }
    }

    bool ssaoEnabled() @property
    {
        return _ssaoEnabled;
    }
    
    void occlusionBufferDetail(float value) @property
    {
        _occlusionBufferDetail = value;
        occlusionView.resize(cast(uint)(view.width * _occlusionBufferDetail), cast(uint)(view.height * _occlusionBufferDetail));
        occlusionNoisyBuffer.resize(occlusionView.width, occlusionView.height);
        occlusionBuffer.resize(occlusionView.width, occlusionView.height);
    }
    float occlusionBufferDetail() @property
    {
        return _occlusionBufferDetail;
    }
    
    this(EventManager eventManager, Owner owner)
    {
        super(eventManager, owner);
        
        outputBuffer = New!Framebuffer(eventManager.windowWidth, eventManager.windowHeight, FrameBufferFormat.RGBA16F, true, this);
        
        gbuffer = New!GBuffer(view.width, view.height, outputBuffer, this);
        
        passShadow = New!PassShadow(pipeline);
        
        passBackground = New!PassBackground(pipeline, gbuffer);
        passBackground.view = view;
        
        terrainNormalBuffer = New!Framebuffer(eventManager.windowWidth, eventManager.windowHeight, FrameBufferFormat.RGBA16F, false, this);
        terrainTexcoordBuffer = New!Framebuffer(eventManager.windowWidth, eventManager.windowHeight, FrameBufferFormat.RGB32F, false, this);
        passTerrain = New!PassTerrain(pipeline, gbuffer, terrainNormalBuffer, terrainTexcoordBuffer);
        passTerrain.view = view;
        
        passStaticGeometry = New!PassGeometry(pipeline, gbuffer);
        passStaticGeometry.view = view;
        
        passDecal = New!PassDecal(pipeline, gbuffer);
        passDecal.view = view;
        
        passDynamicGeometry = New!PassGeometry(pipeline, gbuffer);
        passDynamicGeometry.view = view;
        
        occlusionView = New!RenderView(0, 0, cast(uint)(view.width * _occlusionBufferDetail), cast(uint)(view.height * _occlusionBufferDetail), this);
        passOcclusion = New!PassOcclusion(pipeline, gbuffer);
        passOcclusion.view = occlusionView;
        occlusionNoisyBuffer = New!Framebuffer(occlusionView.width, occlusionView.height, FrameBufferFormat.R8, false, this);
        passOcclusion.outputBuffer = occlusionNoisyBuffer;
        
        denoiseShader = New!DenoiseShader(this);
        passOcclusionDenoise = New!FilterPass(pipeline, denoiseShader);
        passOcclusionDenoise.view = occlusionView;
        passOcclusionDenoise.inputBuffer = occlusionNoisyBuffer;
        occlusionBuffer = New!Framebuffer(occlusionView.width, occlusionView.height, FrameBufferFormat.R8, false, this);
        passOcclusionDenoise.outputBuffer = occlusionBuffer;
        
        passEnvironment = New!PassEnvironment(pipeline, gbuffer);
        passEnvironment.view = view;
        passEnvironment.outputBuffer = outputBuffer;
        passEnvironment.occlusionBuffer = occlusionBuffer;
        
        passLight = New!PassLight(pipeline, gbuffer);
        passLight.view = view;
        passLight.outputBuffer = outputBuffer;
        passLight.occlusionBuffer = occlusionBuffer;
        
        passForward = New!PassForward(pipeline, gbuffer);
        passForward.view = view;
        passForward.outputBuffer = outputBuffer;
        
        passParticles = New!PassParticles(pipeline, gbuffer);
        passParticles.view = view;
        passParticles.outputBuffer = outputBuffer;
        passParticles.gbuffer = gbuffer;
    }

    override void scene(Scene s)
    {
        passShadow.group = s.spatial;
        passShadow.lightGroup = s.lights;
        passBackground.group = s.background;
        passTerrain.group = s.spatial;
        passStaticGeometry.group = s.spatialOpaqueStatic;
        passDecal.group = s.decals;
        passDynamicGeometry.group = s.spatialOpaqueDynamic;
        passLight.groupSunLights = s.sunLights;
        passLight.groupAreaLights = s.areaLights;
        passForward.group = s.spatialTransparent;
        passParticles.group = s.spatial;
        
        pipeline.environment = s.environment;
    }

    override void update(Time t)
    {
        passShadow.camera = activeCamera;
        
        passOcclusion.ssaoShader.samples = ssaoSamples;
        passOcclusion.ssaoShader.radius = ssaoRadius;
        passOcclusion.ssaoShader.power = ssaoPower;
        denoiseShader.factor = ssaoDenoise;
        
        super.update(t);
    }
    
    override void render()
    {
        super.render();
    }

    override void setViewport(uint x, uint y, uint w, uint h)
    {
        super.setViewport(x, y, w, h);
        outputBuffer.resize(view.width, view.height);
        gbuffer.resize(view.width, view.height);
        occlusionView.resize(cast(uint)(view.width * _occlusionBufferDetail), cast(uint)(view.height * _occlusionBufferDetail));
        occlusionNoisyBuffer.resize(occlusionView.width, occlusionView.height);
        occlusionBuffer.resize(occlusionView.width, occlusionView.height);
        terrainNormalBuffer.resize(view.width, view.height);
        terrainTexcoordBuffer.resize(view.width, view.height);
        passTerrain.resize(view.width, view.height);
        passForward.resize(view.width, view.height);
    }
}
