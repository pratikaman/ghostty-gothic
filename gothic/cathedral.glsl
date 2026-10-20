// Cathedral: Ghostty Gothic's default custom shader.
//
// The terminal is a pointed-arch window set in an ashlar stone wall.
// Light falls through stained glass in slow coloured shafts, dust drifts
// in it, and a candle burns at the cursor. Every effect is masked to
// background-coloured pixels, so glyphs are never tinted or dimmed.

// Knobs.
const bool Y_DOWN = true;         // Metal (macOS) hands shaders y-down coords; false for OpenGL
const float ARCH_SPRING = 0.34;   // height (0..1) where the arch starts to curve
const float ARCH_RADIUS = 0.68;   // > 0.5 is pointed; with ARCH_SPRING it puts the apex at the top
const float WALL_SHADE = 0.55;    // background brightness outside the arch
const float STONE = 0.045;        // how visible the ashlar blocks are
const float RIM = 0.22;           // carved moulding along the arch
const float SHAFTS = 0.07;        // stained-glass light strength
const float DUST = 0.30;
const float CANDLE = 0.15;
const float CANDLE_REACH = 7.0;   // glow radius, in cursor heights

const vec3 LIMESTONE = vec3(0.83, 0.77, 0.67);
const vec3 FLAME = vec3(1.0, 0.58, 0.20);

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise1(float x) {
    float i = floor(x);
    float f = fract(x);
    return mix(hash(vec2(i, 1.7)), hash(vec2(i + 1.0, 1.7)), f * f * (3.0 - 2.0 * f));
}

// Distance to the arch outline in uv units, negative inside. The arch is
// the intersection of two discs whose centres sit on the springing line.
float archDist(vec2 uv) {
    float walls = max(-uv.x, uv.x - 1.0);
    if (uv.y < ARCH_SPRING) return walls;
    vec2 q = vec2(uv.x, uv.y - ARCH_SPRING);
    return max(length(q - vec2(ARCH_RADIUS, 0.0)),
               length(q - vec2(1.0 - ARCH_RADIUS, 0.0))) - ARCH_RADIUS;
}

// Staggered courses of dressed stone: ~1 on a block face, negative in the joints.
float ashlar(vec2 p) {
    const vec2 block = vec2(150.0, 60.0);
    float course = floor(p.y / block.y);
    p.x += mod(course, 2.0) * block.x * 0.5;
    vec2 cell = floor(p / block);
    vec2 f = p - cell * block;
    float edge = min(min(f.x, block.x - f.x), min(f.y, block.y - f.y));
    float joint = 1.0 - smoothstep(1.0, 3.0, edge);
    return mix(0.55 + 0.45 * hash(cell), -0.8, joint);
}

vec3 glass(float i) {
    float k = mod(i, 4.0);
    if (k < 1.0) return vec3(0.20, 0.38, 1.00);  // cobalt
    if (k < 2.0) return vec3(0.95, 0.22, 0.28);  // ruby
    if (k < 3.0) return vec3(1.00, 0.74, 0.28);  // gilt
    return vec3(0.65, 0.38, 0.92);               // amethyst
}

// Light shafts falling from the upper left; returns colour * strength.
vec3 shafts(vec2 uv, float t, out float mask) {
    vec2 p = vec2(uv.x * iResolution.x / iResolution.y, uv.y);
    float s = dot(p, normalize(vec2(1.0, 0.42))) * 5.0 + 0.15 * sin(t * 0.07);
    float i = floor(s);
    float f = fract(s);
    float w = 0.18 + 0.22 * hash(vec2(i, 9.0));
    float band = smoothstep(0.5 - w, 0.5 - w * 0.4, f) * (1.0 - smoothstep(0.5 + w * 0.4, 0.5 + w, f));
    float lit = step(0.3, hash(vec2(i, 4.0))) * (0.6 + 0.4 * noise1(t * 0.05 + i * 3.1));
    mask = band * lit * smoothstep(0.0, 1.0, uv.y);
    return glass(i) * mask;
}

float dust(vec2 p, float t) {
    const float cell = 34.0;
    p.y += t * 7.0;  // pattern rises, so motes sink
    vec2 c = floor(p / cell);
    vec2 f = p - c * cell;
    float h = hash(c);
    vec2 at = vec2(hash(c + 3.1), hash(c + 7.7)) * (cell - 8.0) + 4.0;
    at.x += sin(t * 0.6 + h * 40.0) * 3.0;
    float twinkle = 0.5 + 0.5 * sin(t * 1.7 + h * 90.0);
    return step(h, 0.16) * (1.0 - smoothstep(0.8, 2.4, length(f - at))) * twinkle;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);
    float bg = 1.0 - smoothstep(0.02, 0.09, distance(term.rgb, iBackgroundColor));

    // The architecture is laid out y-up, whatever the renderer uses.
    vec2 p = vec2(fragCoord.x, Y_DOWN ? iResolution.y - fragCoord.y : fragCoord.y);
    vec2 uv = p / iResolution.xy;

    float d = archDist(uv);
    float dpx = d / max(fwidth(d), 1e-5);
    float outside = smoothstep(-1.0, 1.0, dpx);
    float curved = smoothstep(ARCH_SPRING - 0.04, ARCH_SPRING + 0.04, uv.y);

    // Candle at the cursor; it gutters when the split loses focus.
    // The cursor uniform is already in the renderer's own space.
    vec2 cur = iCurrentCursor.xy + vec2(iCurrentCursor.z, -iCurrentCursor.w) * 0.5;
    float reach = max(iCurrentCursor.w, 1.0) * CANDLE_REACH;
    vec2 dc = fragCoord - cur;
    float flicker = 0.8 + 0.2 * noise1(iTime * 9.0) * noise1(iTime * 3.3 + 5.0);
    float candle = exp(-dot(dc, dc) / (reach * reach)) * flicker * mix(0.35, 1.0, float(iFocus));

    vec3 base = iBackgroundColor;

    // Stone wall outside the arch, more visible where the candle reaches.
    vec3 wall = base * WALL_SHADE + LIMESTONE * STONE * ashlar(p) * (1.0 + 3.0 * candle);

    // Inside: stained-glass shafts with dust motes drifting through them.
    float shaftMask;
    vec3 light = shafts(uv, iTime, shaftMask);
    vec3 nave = base + light * SHAFTS + LIMESTONE * dust(p, iTime) * shaftMask * DUST;

    // Moulding: a bright fillet and a fainter roll just inside the arch.
    float rim = (1.0 - smoothstep(0.0, 1.5, abs(dpx + 4.0)))
              + 0.5 * (1.0 - smoothstep(0.0, 2.5, abs(dpx + 14.0)));
    nave += LIMESTONE * rim * RIM * curved;

    vec3 scene = mix(nave, wall, outside) + FLAME * candle * CANDLE;
    fragColor = vec4(mix(term.rgb, scene, bg), term.a);
}
