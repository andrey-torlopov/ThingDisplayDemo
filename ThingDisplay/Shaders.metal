#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float4 color;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4 color;
    float3 cameraPosition;
};

vertex VertexOut vertex_main(Vertex in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;

    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;

    // Transform normal
    float3x3 normalMatrix = float3x3(uniforms.modelMatrix[0].xyz,
                                      uniforms.modelMatrix[1].xyz,
                                      uniforms.modelMatrix[2].xyz);
    out.normal = normalize(normalMatrix * in.normal);
    out.color = uniforms.color;

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(1)]]) {
    // Light direction
    float3 lightDir = normalize(float3(0.5, 1.0, 0.8));
    float3 viewDir = normalize(uniforms.cameraPosition - in.worldPosition);

    // Diffuse lighting
    float diff = max(dot(in.normal, lightDir), 0.0);

    // Specular lighting
    float3 halfwayDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(in.normal, halfwayDir), 0.0), 32.0);

    // Ambient
    float3 ambient = 0.3 * in.color.rgb;
    float3 diffuse = 0.6 * diff * in.color.rgb;
    float3 specular = 0.3 * spec * float3(1.0);

    float3 result = ambient + diffuse + specular;

    // Add some translucency effect for organic look
    float fresnel = pow(1.0 - max(dot(viewDir, in.normal), 0.0), 3.0);
    result += fresnel * 0.2 * in.color.rgb;

    return float4(result, in.color.a);
}
