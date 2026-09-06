Shader "CosmicStars/BlackHole URP"
{
    Properties
    {
        Rs ("Schwarzschild Radius", Float) = 4.0
        gravity_strength ("Gravity Strength", Float) = 1.0
        steps ("Raymarch Steps", Int) = 320
        disk_tilt ("Disk Tilt", Float) = -0.3
        disk_inner_radius_ratio ("Disk Inner Radius Ratio", Float) = 2.5
        disk_outer_radius_ratio ("Disk Outer Radius Ratio", Float) = 6.0
        disk_thickness_ratio ("Disk Thickness Ratio", Float) = 0.55
        disk_noise_amount ("Disk Noise Amount", Float) = 1.2
        disk_temperature_scale ("Disk Temperature Scale", Float) = 0.84
        output_exposure ("Output Exposure", Float) = 1.6
        noise_texture_scale ("Noise Texture Scale", Float) = 0.15
        noise_mode ("Noise Mode (0 Texture, 1 Procedural)", Int) = 1
        noise_hybrid_split ("Noise Hybrid Split", Int) = 3
        noise_detail_footprint ("Noise Detail Footprint", Float) = 0.0015
        disk_domain_warp ("Disk Domain Warp", Float) = 0.6

        [NoScaleOffset] sky_texture ("Sky Texture", 2D) = "black" {}
        [NoScaleOffset] blackbody_lut ("Blackbody LUT", 2D) = "black" {}
        [NoScaleOffset] far_field_deflection_lut ("Far Field Deflection LUT", 2D) = "black" {}
        [NoScaleOffset] noise_texture ("3D Noise Texture", 3D) = "" {}
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Overlay"
            "RenderType" = "Transparent"
        }

        Pass
        {
            Name "BlackHoleRaymarch"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex BlackHoleVertex
            #pragma fragment BlackHoleFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(sky_texture);
            SAMPLER(sampler_sky_texture);
            TEXTURE2D(blackbody_lut);
            SAMPLER(sampler_blackbody_lut);
            TEXTURE2D(far_field_deflection_lut);
            SAMPLER(sampler_far_field_deflection_lut);
            TEXTURE3D(noise_texture);
            SAMPLER(sampler_noise_texture);

            CBUFFER_START(UnityPerMaterial)
                float Rs;
                float gravity_strength;
                int steps;
                float disk_tilt;
                float disk_inner_radius_ratio;
                float disk_outer_radius_ratio;
                float disk_thickness_ratio;
                float disk_noise_amount;
                float disk_temperature_scale;
                float output_exposure;
                float noise_texture_scale;
                int noise_mode;
                int noise_hybrid_split;
                float noise_detail_footprint;
                float disk_domain_warp;
            CBUFFER_END

            struct BlackHoleAttributes
            {
                float3 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct BlackHoleVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            BlackHoleVaryings BlackHoleVertex(BlackHoleAttributes input)
            {
                BlackHoleVaryings output;
                // Unity's built-in Quad is 1x1 in object space; expand it to clip-space fullscreen.
                output.positionCS = float4(input.positionOS.xy * 2.0, 0.0, 1.0);
                return output;
            }

            #include "BlackHoleURP.hlsl"
            ENDHLSL
        }
    }
}
