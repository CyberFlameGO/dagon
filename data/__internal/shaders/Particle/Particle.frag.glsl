#version 400 core

in vec3 eyePosition;
in vec2 texCoord;

in vec3 worldPosition;
in vec3 worldView;

in vec4 currPosition;
in vec4 prevPosition;

uniform mat4 viewMatrix;
uniform mat4 invProjectionMatrix;

uniform bool shaded;
uniform vec3 sunDirection;
uniform vec4 sunColor;
uniform float sunEnergy;

#include <unproject.glsl>
#include <gamma.glsl>
#include <cotangentFrame.glsl>

/*
 * Diffuse color subroutines.
 * Used to switch color/texture.
 */
subroutine vec4 srtColor(in vec2 uv);

uniform vec4 diffuseVector;
subroutine(srtColor) vec4 diffuseColorValue(in vec2 uv)
{
    return diffuseVector;
}

uniform sampler2D diffuseTexture;
subroutine(srtColor) vec4 diffuseColorTexture(in vec2 uv)
{
    return texture(diffuseTexture, uv);
}

subroutine uniform srtColor diffuse;

/*
 * Normal mapping subroutines.
 */
subroutine vec3 srtNormal(in vec2 uv, in float ysign, in mat3 tangentToEye);

uniform vec3 normalVector;
subroutine(srtNormal) vec3 normalValue(in vec2 uv, in float ysign, in mat3 tangentToEye)
{
    vec3 tN = normalVector;
    tN.y *= ysign;
    return normalize(tangentToEye * tN);
}

uniform sampler2D normalTexture;
subroutine(srtNormal) vec3 normalMap(in vec2 uv, in float ysign, in mat3 tangentToEye)
{
    vec3 tN = normalize(texture(normalTexture, uv).rgb * 2.0 - 1.0);
    tN.y *= ysign;
    return normalize(tangentToEye * tN);
}

subroutine(srtNormal) vec3 normalFunctionHemisphere(in vec2 uv, in float ysign, in mat3 tangentToEye)
{
    // Generate spherical tangent-space normal
    vec2 p = uv * 2.0 - 1.0;
    if (dot(p, p) >= 1.0)
        p = normalize(p) * 0.999; // small bias to fight aliasing
    float vz = sqrt(1.0 - p.x * p.x - p.y * p.y);
    vec3 tN = vec3(p.x, p.y, vz);
    return normalize(tangentToEye * tN);
}

subroutine uniform srtNormal normal;


uniform vec2 viewSize;
uniform sampler2D depthTexture;

uniform vec4 particleColor;
uniform float particleAlpha;
uniform bool alphaCutout;
uniform float alphaCutoutThreshold;
uniform vec3 particlePosition;

uniform vec4 fogColor;
uniform float fogStart;
uniform float fogEnd;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 fragVelocity;

void main()
{
    vec2 screenTexcoord = gl_FragCoord.xy / viewSize;
    float depth = texture(depthTexture, screenTexcoord).x;
    vec3 referenceEyePos = unproject(invProjectionMatrix, vec3(screenTexcoord, depth));
    vec3 E = normalize(-eyePosition);
    
    vec3 N = normalize(-particlePosition);
    mat3 tangentToEye = cotangentFrame(N, eyePosition, texCoord);
    N = normal(texCoord, -1.0, tangentToEye);

    vec3 worldN = N * mat3(viewMatrix);
    
    // TODO: ambient
    vec3 ambient = vec3(0.0, 0.0, 0.0);
    const float wrapFactor = 0.5;
    vec3 radiance = shaded? 
        ambient + toLinear(sunColor.rgb) * max(dot(N, sunDirection) + wrapFactor, 0.0) / (1.0 + wrapFactor) * sunEnergy :
        vec3(1.0);
    
    // TODO: make uniform
    const float softDistance = 3.0;
    float soft = alphaCutout? 1.0 : clamp((eyePosition.z - referenceEyePos.z) / softDistance, 0.0, 1.0);
        
    vec4 diff = diffuse(texCoord);
    vec3 outColor = radiance * toLinear(diff.rgb) * toLinear(particleColor.rgb);
    float outAlpha = diff.a * particleColor.a * particleAlpha * soft;
    
    if (alphaCutout && outAlpha <= alphaCutoutThreshold)
        discard;
    
    // Fog
    float linearDepth = abs(eyePosition.z);
    float fogFactor = clamp((fogEnd - linearDepth) / (fogEnd - fogStart), 0.0, 1.0);
    outColor = mix(toLinear(fogColor.rgb), outColor, fogFactor);
    
    // Velocity
    vec2 posScreen = (currPosition.xy / currPosition.w) * 0.5 + 0.5;
    vec2 prevPosScreen = (prevPosition.xy / prevPosition.w) * 0.5 + 0.5;
    vec2 screenVelocity = posScreen - prevPosScreen;
    
    fragColor = vec4(outColor, outAlpha);
    fragVelocity = vec4(screenVelocity, 0.0, 1.0);
}
