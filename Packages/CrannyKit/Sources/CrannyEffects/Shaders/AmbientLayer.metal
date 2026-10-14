// CrannyEffects/Shaders/AmbientLayer.metal — the vertex stage of the dedicated ambient Metal layer
// (AmbientRenderer.swift). One full-screen triangle; each effect's fragment function lives next to its field.
#include <metal_stdlib>
#include "CrannyShaders.h"
using namespace metal;

/// A triangle that covers the whole drawable (vertices 0, 1, 2 → (−1,−1), (3,−1), (−1,3)).
vertex cranny::AmbientVertexOut ambientVertex(uint vertexID [[vertex_id]]) {
    float2 p = float2(float((vertexID << 1) & 2), float(vertexID & 2));
    cranny::AmbientVertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}
