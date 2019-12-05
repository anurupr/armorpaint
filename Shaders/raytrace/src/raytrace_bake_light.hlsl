
#include "std/rand.hlsl"
#include "std/math.hlsl"
#include "std/attrib.hlsl"

struct Vertex {
	float3 position;
	float3 normal;
	float2 tex;
};

struct RayGenConstantBuffer {
	float4 v0; // frame, strength, radius, offset
	float4 v1; // envstr
	float4 v2;
	float4 v3;
	float4 v4;
};

struct RayPayload {
	float4 color;
	float3 ray_origin;
	float3 ray_dir;
};

RWTexture2D<float4> render_target : register(u0);
RaytracingAccelerationStructure scene : register(t0);
ByteAddressBuffer indices : register(t1);
StructuredBuffer<Vertex> vertices : register(t2);
ConstantBuffer<RayGenConstantBuffer> constant_buffer : register(b0);

Texture2D<float4> mytexture0 : register(t3);
Texture2D<float4> mytexture1 : register(t4);
Texture2D<float4> mytexture2 : register(t5);
Texture2D<float4> mytexture_env : register(t6);
Texture2D<float4> mytexture_sobol : register(t7);
Texture2D<float4> mytexture_scramble : register(t8);
Texture2D<float4> mytexture_rank : register(t9);

static const int SAMPLES = 64;
static uint seed = 0;

[shader("raygeneration")]
void raygeneration() {
	float2 xy = DispatchRaysIndex().xy + 0.5f;
	float3 pos = mytexture0.Load(uint3(xy, 0)).rgb;
	float3 nor = mytexture1.Load(uint3(xy, 0)).rgb;

	RayPayload payload;

	RayDesc ray;
	ray.TMin = constant_buffer.v0.w * 0.01;
	ray.TMax = constant_buffer.v0.z * 10.0;
	ray.Origin = pos;

	float3 accum = float3(0, 0, 0);

	for (int i = 0; i < SAMPLES; ++i) {
		ray.Direction = cos_weighted_hemisphere_direction(nor, i, seed, constant_buffer.v0.x, mytexture_sobol, mytexture_scramble, mytexture_rank);
		seed += 1;
		TraceRay(scene, RAY_FLAG_FORCE_OPAQUE, ~0, 0, 1, 0, ray, payload);
		accum += payload.color.rgb;
	}

	accum /= SAMPLES;

	float3 color = float3(render_target[DispatchRaysIndex().xy].xyz);
	if (constant_buffer.v0.x == 0) {
		color = accum.xyz;
	}
	else {
		float a = 1.0 / constant_buffer.v0.x;
		float b = 1.0 - a;
		color = color * b + accum.xyz * a;
	}
	render_target[DispatchRaysIndex().xy] = float4(color.xyz, 0.0f);
}

[shader("closesthit")]
void closesthit(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attr) {
	const uint triangleIndexStride = 12; // 3 * 4
	uint base_index = PrimitiveIndex() * triangleIndexStride;
	uint3 indices_sample = indices.Load3(base_index);

	float3 vertex_normals[3] = {
		float3(vertices[indices_sample[0]].normal),
		float3(vertices[indices_sample[1]].normal),
		float3(vertices[indices_sample[2]].normal)
	};
	float3 n = normalize(hit_attribute(vertex_normals, attr));

	float2 vertex_uvs[3] = {
		float2(vertices[indices_sample[0]].tex),
		float2(vertices[indices_sample[1]].tex),
		float2(vertices[indices_sample[2]].tex)
	};
	float2 tex_coord = hit_attribute2d(vertex_uvs, attr);

	uint2 size;
	mytexture2.GetDimensions(size.x, size.y);
	float3 texpaint2 = pow(mytexture2.Load(uint3(tex_coord * size, 0)).rgb, 2.2); // layer base
	payload.color.rgb = texpaint2.rgb;
}

[shader("miss")]
void miss(inout RayPayload payload) {
	float2 tex_coord = equirect(WorldRayDirection());
	uint2 size;
	mytexture_env.GetDimensions(size.x, size.y);
	float3 texenv = mytexture_env.Load(uint3(tex_coord * size, 0)).rgb * constant_buffer.v1.x;
	payload.color = float4(texenv.rgb, -1);
}
