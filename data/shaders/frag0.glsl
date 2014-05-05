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

const float PI = 3.14159265359;

uniform vec2 resolution;

uniform float halfbeat; // in milliseconds
uniform float beat;

uniform float time; // milliseconds since the start of the draw() loop
uniform float threshold; // pivot for calculating gain expression, e.g. contrast

// 5/2014: This may look like the Bad Way of doing things but--
// - Processing shader API does not support array binding
// - GLSL ES does not support looping over arrays (in GLSL < 4.0 array indices are const)
//   http://stackoverflow.com/questions/12030711/glsl-array-of-textures-of-differing-size/

uniform sampler2D stream0;
uniform sampler2D stream1;
uniform sampler2D stream2;

uniform float period0; // in ms
uniform float period1;
uniform float period2;

uniform float phase0; // in ms
uniform float phase1;
uniform float phase2;

uniform float gain0; // 1-based, i.e. a coefficient
uniform float gain1;
uniform float gain2;

uniform vec3 balance0; // RGB for beat expression
uniform vec3 balance1;
uniform vec3 balance2;

// TODO
// halfbeat0 1 2
// threshold0 1 2

// Beat phase in [0,1] -- 0 off-beat, 1 at center of beat
float beatPhase( float period, float phase ) {
	return clamp( halfbeat - abs( mod( time, period + beat ) - phase ), 0., halfbeat ) / halfbeat;
		// + beat to handle edge-of-period half-beat problem
}

// Easing to simulate Fourier modeling of beat shape
// - Start with beat phase in [0,1]
// - Map it to [ sin(-π/2), sin(π/2) ]
// - Map that to [ 1., gain ]
float easing( float phase, float gain ) {
	float pulse = .5 + .5 * sin( PI * ( phase - .5 ) );
	return pulse * ( gain - 1. ) + 1.;
}

void main() {
	// We could use vertTexCoord and texOffset (Processing uniforms),
	// but it feels more portable to roll our own

	// Invert y-axis -- Processing y-axis runs top to bottom
	vec2 pos = vec2( gl_FragCoord.s / resolution.s, 1. - (gl_FragCoord.t / resolution.t) );

	// 1-texel offset for convolution filtering
	vec2 off = vec2( 1. / resolution.s, 1. / resolution.t );

	// Sample texture data for current fragment
	vec4 c0 = texture2D( stream0, pos );
	vec4 c1 = texture2D( stream1, pos );
	vec4 c2 = texture2D( stream2, pos );

	//
	// For each stream, do something special if its oscillator is on-beat
	// Right now the something special is just heightened contrast

	// Inspired by http://glsl.heroku.com/e#15220.0

	float beatPhase0 = beatPhase( period0, phase0 );
	float beatPhase1 = beatPhase( period1, phase1 );
	float beatPhase2 = beatPhase( period2, phase2 );

	// TODO --
	// Add a flare, drawing in the color values from neighboring texels
	// Look at http://glsl.heroku.com/e#15220.0 --
	// Maybe use an exponential distance decay from current position

	// TODO --
	// turn repeated contrast lines into a fn

	if ( beatPhase0 > 0. ) {
		c0.rgb = ( c0.rgb - threshold ) * easing( beatPhase0, gain0 ) + threshold;
		c0.r *= balance0.r;
		c0.g *= balance0.g;
		c0.b *= balance0.b;
	}
	if ( beatPhase1 > 0. ) {
		c1.rgb = ( c1.rgb - threshold ) * easing( beatPhase1, gain1 ) + threshold;
		c1.r *= balance1.r;
		c1.g *= balance1.g;
		c1.b *= balance1.b;
	}
	if ( beatPhase2 > 0. ) {
		c2.rgb = ( c2.rgb - threshold ) * easing( beatPhase2, gain2 ) + threshold;
		c2.r *= balance2.r;
		c2.g *= balance2.g;
		c2.b *= balance2.b;
	}

	// TODO: Rethink
	// Blend the textures
	// We use a lighten blend, not a linear tween
	// The video streams are characterized by dark backgrounds with bright shapes
	// So a tween would mute the colors
	vec4 blend = max( c0, max( c1, c2 ) );

	gl_FragColor = vec4( blend.rgb, 1. ) ; //* vertColor;
}



	// TODO -- Motion blur! Use offsets at multiple steps from the current fragment for bigger blur
	// http://lodev.org/cgtutor/filtering.html
	// Modularize with arrays -- radius-2 texel matrix == [25], rad-2 convolution matrix, pass those in w offset, get out convolved color
	// Or for efficiency just [5] for the row, if we're doing transverse motion blur
	// -- and the gain is represented by blur radius and duration ...

