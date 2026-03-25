shader_type spatial;

render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;



uniform float Rs = 0.5;

uniform float gravity_strength = 1.0;

uniform int steps = 64; 

uniform float base_step = 0.05;

uniform sampler2D sky_texture : filter_nearest;





const int MAX_STEPS = 512;



// 顶点函数：强制让这个 Quad 铺满 NDC 坐标（全屏）//AI策略

void vertex() {

    POSITION = vec4(VERTEX.xy, 1.0, 1.0);

}



vec3 calc_acceleration(vec3 x, float L2) {

    float r2 = dot(x, x);

    float r = sqrt(r2);

    float r5 = max(r2 * r2 * r, 1e-6);

    return - (1.5 * Rs * gravity_strength * L2 / r5) * x;//由施瓦西度规导出的拉氏量

}



void rk4_step(inout vec3 x, inout vec3 v, float dl, float L2) {//四阶龙格库塔积分，inout随时传入数值

    vec3 k1_x = v;

    vec3 k1_v = calc_acceleration(x, L2);

    vec3 k2_x = v + k1_v * (dl * 0.5);

    vec3 k2_v = calc_acceleration(x + k1_x * (dl * 0.5), L2);

    vec3 k3_x = v + k2_v * (dl * 0.5);

    vec3 k3_v = calc_acceleration(x + k2_x * (dl * 0.5), L2);

    vec3 k4_x = v + k3_v * dl;

    vec3 k4_v = calc_acceleration(x + k3_x * dl, L2);

    x += (k1_x + 2.0 * k2_x + 2.0 * k3_x + k4_x) * (dl / 6.0);

    v += (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v) * (dl / 6.0);

}



// 吸积盘体积步进函数（不会写噪声）

vec4 calculate_disk_color(vec4 fragColor, float steplength, vec3 RayPos, float RIn, float ROut) {

    float PosR = length(RayPos.xz);

    float PosZ = RayPos.y; 



    vec4 color = vec4(0.0);

    

    if (PosR < ROut && PosR > RIn) {

        

       //形态和颜色

        float t = (PosR - RIn) / (ROut - RIn);

        vec3 base_color = mix(vec3(1.0, 0.9, 0.5), vec3(0.8, 0.2, 0.0), t);

        float vertical_falloff = exp2(-abs(PosZ) * 5.77 / Rs); 

        

        float density = (1.0 - t) * vertical_falloff; 

        

     

        color.rgb = base_color * density * (steplength / Rs) * 5.0; 

        color.a = density * (steplength / Rs) * 2.0; 

    }

    

    return fragColor + color * (1.0 - fragColor.a);

}



void fragment() {

   

    vec2 ndc = SCREEN_UV * 2.0 - 1.0;

    float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;

    

    

    vec3 fwd = -INV_VIEW_MATRIX[2].xyz;

    vec3 rgt = INV_VIEW_MATRIX[0].xyz;

    vec3 up  = INV_VIEW_MATRIX[1].xyz;

    

    

    vec3 rd = normalize(fwd * 1.5 + rgt * ndc.x * aspect + up * ndc.y);

    

    // 把黑洞固定在世界原点 (0,0,0)

    vec3 bh_center_ws = vec3(0.0, 0.0, 0.0);

    vec3 x = CAMERA_POSITION_WORLD - bh_center_ws;

    vec3 v = rd;



    vec3 L_vec = cross(x, v);

    float L2 = dot(L_vec, L_vec);



    bool hit_hole = false;

    float real_escape_radius = 500.0;



   // 吸积盘的光线TAA

    vec4 disk_col_accum = vec4(0.0);

    float dither = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453123);



    

    float initial_dl = base_step * (max(length(x), Rs * 0.5) + 0.01 * length(x) * length(x));

    rk4_step(x, v, initial_dl * dither, L2);

    

    // 定义吸积盘的内外大小 (相对于黑洞视界 Rs )

    float RIn = Rs * 2.5; 

    float ROut = Rs * 8.0;



    for (int i = 0; i < MAX_STEPS; i++) {

        if (i >= steps) break;

        float r = length(x);

        if (r <= Rs) { hit_hole = true; break; }

        if (r >= real_escape_radius) break;



        float dl = base_step * (max(r, Rs * 0.5) + 0.01 * r * r);

        

        

        disk_col_accum = calculate_disk_color(disk_col_accum, dl, x, RIn, ROut);

        

    

        if (disk_col_accum.a >= 1.0) {

            break;

        }



        rk4_step(x, v, dl, L2);

    }



    if (!hit_hole && dot(x, v) < 0.0) hit_hole = true;



    vec3 out_col = vec3(0.0);

    if (!hit_hole) {

        vec3 ray_dir = normalize(v);

        // 采样天空盒

        float phi = atan(ray_dir.x, -ray_dir.z);

        float theta = acos(clamp(ray_dir.y, -1.0, 1.0));

        vec2 uv = vec2(phi / (2.0 * PI) + 0.5, theta / PI);

        out_col = texture(sky_texture, uv).rgb;

    }



   

    ALBEDO = mix(out_col, disk_col_accum.rgb, clamp(disk_col_accum.a, 0.0, 1.0));

}