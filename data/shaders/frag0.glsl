// Zeitgeber v0.0001

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

// _COLOR_ vs _TEXTURE_ depends on whether we're using shader() or filter()
// (d.h., whether there's an underlying pixels[] to which we're applying the filter)
// With TEXTURE you get a builtin sampler called "texture"

#define PROCESSING_COLOR_SHADER
//#define PROCESSING_TEXTURE_SHADER

const int nStreams = 3;

uniform vec2 resolution;
uniform int halfbeat; // in ms
uniform int beat;

uniform int time; // ms since the start of the draw() loop

// This may look like the Bad Way of doing things but--
// (5/2014) Processing shader API does not support array binding
// + GLSL ES does not support looping over arrays (in GLSL < 4.0 array indices are const)
// http://stackoverflow.com/questions/12030711/glsl-array-of-textures-of-differing-size/

uniform sampler2D stream0;
uniform sampler2D stream1;
uniform sampler2D stream2;

uniform int period0; // in ms
uniform int period1;
uniform int period2;

uniform int phase0; // in ms
uniform int phase1;
uniform int phase2;

uniform float gain0; // 1-based, i.e. a coefficient
uniform float gain1;
uniform float gain2;

uniform vec3 balance0; // RGB for beat expression
uniform vec3 balance1;
uniform vec3 balance2;

bool onBeat( int period, int phase ) {
	return abs( time % ( period + beat ) - phase ) < halfbeat;
		// + beat to handle edge-of-period half-beat problem
}


// Perlin's Hermite 6x^5 - 15x^4 + 10x^3
float smootherstep( float a, float b, float x ) {
    // Scale, and clamp x to 0..1 range
    x = clamp( (x - a) / (b - a), 0., 1. );
    // Evaluate polynomial
    return x*x*x * (x * ( x*6 - 15 ) + 10);
}

void main() {
	// We could use vertTexCoord and texOffset (Processing uniforms),
	// but it feels more portable to roll our own

	// Invert y-axis -- Processing y-axis runs top to bottom
	vec2 pos = vec2( gl_FragCoord.s / resolution.s, 1. - (gl_FragCoord.t / resolution.t) );

	// 1-texel offset for convolution filtering
	vec2 off = vec2( 1. / resolution.s, 1. / resolution.t );

	// Each stream has a tactus, and it flares on the beat
	// as in http://glsl.heroku.com/e#15220.0 ... or contrast increases --

	// Mathematical modeling of heartbeat-type spike rhythm
	// http://www.intmath.com/blog/math-of-ecgs-fourier-series/4281
	// Rather than calculate the Fourier expansion for O(streams) * O(pixels)
	// can we simply fake it? If the R pulse lasts ~40ms
	// if ( mod(time - phase * period, period) < .04 )

	// Could we also use a different kind of periodicity? Maybe physiological tremor?

	// Contrast
	// color.rgb = ( (color.rgb - threshold) * max(contrast, 0) ) + threshold; // threshold normally .5
	// For us, contrast == gain ≥ 1, so we can dispense with the max() ... maybe threshold == .8?
	// Or use a red-shifting flare as http://glsl.heroku.com/e#15220.0
	// -- just use different coefficients for the contrast on the r g and b

	// Streams all have different intrinsic tau ... What keeps them entrained?
	// As you reach out (via the Leap) a particular stream reaches back to you (via gain, period and speed?)
	// What if the Leaps are tuned to the streams in random and changing fashion?

	vec4 s0 = texture2D(stream0, pos);
	vec4 s1 = texture2D(stream1, pos);
	vec4 s2 = texture2D(stream2, pos);

	// We use a lighten blend, not a linear tween
	// The videos are characterized by dark backgrounds against which bright shapes emerge
	// So a tween would mute the colors
	vec4 blend = max( s0, max( s1, s2 ) );

	// gl_FragColor = vec4(blend.rgb, 1.0) * vertColor;
	gl_FragColor.rgb = blend.rgb;
	gl_FragColor.a = 1.;
	//gl_FragColor *= vertColor;
}



	// TODO -- Motion blur! Use offsets at multiple steps from the current fragment for bigger blur
	// http://lodev.org/cgtutor/filtering.html
	// Modularize with arrays -- radius-2 texel matrix == [25], rad-2 convolution matrix, pass those in w offset, get out convolved color
	// Or for efficiency just [5] for the row, if we're doing transverse motion blur
	// -- and the gain is represented by blur radius and duration ...

