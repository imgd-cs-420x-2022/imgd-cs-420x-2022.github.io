void main () {
    float low = bands.r *2.;
    float lowMid = bands.g *2.;
    float midHigh = bands.b *2.;
    float high = bands.a;
    
    
    vec2 cords = uv();
    vec2 normCords = uvN();
    int num = 1;
    
    vec4 sky = vec4(0.);
    sky += vec4(circle( 0., 0., abs(sin(time)/5.) + 0.2, 0.1));
    sky += vec4(circle( sin(time)/5.,cos(time)/5., 0.3/high, 0.3/high));
    sky.g -= 0.5;
    sky.b -= 1.;
    
    
    vec4 ocean = sky;
    float warppedTime = time;
    
    vec2 cords_A = cords * 3.;
    cords_A.x += cos(warppedTime);
    cords_A.y += warppedTime;
    
    vec2 cords_B = cords * 3.;
    cords_B.x += (sin(warppedTime));
    cords_B.y -= warppedTime;
    
    vec2 cords_C = cords * 3.;
    cords_C.x += warppedTime;
    cords_C.y -= warppedTime; 
    
    vec2 cords_D = cords * 3.;
    cords_D.x += sin(warppedTime);
    cords_D.y += cos(warppedTime);
    
    vec4 A = vec4(rmf(cords_A, num));
    vec4 B = vec4(fbm(cords_B, num));
    vec4 C = vec4(vrmf(cords_C, num)); 
    vec4 D = vec4(vfbm(cords_D, num)); 
    vec4 ABC = A + B + C + D + lowMid;
    
    if(cords.y < -0.5){
      ocean.b += 1.0;
      ocean.r += -0.8;
      sky.b -= 1.0;
      sky.r -= -0.8;
    }else if (cords.y < 0.){
      ocean.b -= (1.0 * cords.y * 2.);
      ocean.r -= (-0.8 * cords.y * 2.);
      sky.b += 1.0;
      sky.r += -0.8;
    }
    
    ocean = ocean * + ABC / 5.;
    
    vec4 pixel = ocean;
    
    
    vec4 bop = vec4(circle(-sin(-time)+sin(time/2.), cos(-time), 1., 1.))/2.;
    if(bop.r + bop.g + bop.b > 0.5 + voronoi( cords )){
        bop.r = 0.;
        bop.g = 0.;
    }
    vec4 flop = vec4(circle(sin(time), -cos(time)+sin(time/2.), 1., 1.))/2.;
    if(flop.r + flop.g + flop.b > 0.5 + voronoi( vec2(cords.y, cords.x) )){
        flop.g = 0.;
        flop.b = 0.;
    }
    vec4 rop = vec4(circle(cos(time), cos(-time)+sin(time/2.), 1., 1.))/2.;
    if(rop.r + rop.g + rop.b > 0.5 + voronoi( vec2(cords.y, tan(time)) )){
        rop.r = 0.;
        rop.b = 0.;
    }
    
    vec4 shling;
    vec2 p = uv();
    vec2 p2 = uv();
    vec4 lastFrame = texture2D( backbuffer, p );
    
    float color = 0.; 
    float frequency = 2.;
    float gain = 1.;
    float thickness = 0.05 * midHigh;
    if(thickness > 0.03){
        for( float i = 0.; i < 10.; i++ ) { 
            p.x += (sin( p.y + time * i) * gain) + 1.; 
            p2.x += (sin( p.y + time * i) * gain) - 1.;
            color += abs( thickness / p.x );
            color += abs( thickness / p2.x );
        }
        shling = vec4( color );
        shling = shling/4.;
    }
    
    gl_FragColor = (pixel + bop + flop + rop) + 0.1 + shling;
}
