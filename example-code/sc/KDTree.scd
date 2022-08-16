strong::Big Example::
code::

// using a KDTree to lookup the point on the plot that is nearest to the mouse
(
var ds = FluidDataSet(s).read(FluidFilesPath("../Data/flucoma_corpus.json"));
var tree = FluidKDTree(s).fit(ds);
ds.dump({
	arg dict;
	var xybuf = Buffer.alloc(s,2);
	var slicePoints = Buffer.read(s,FluidFilesPath("../Data/flucoma_corpus_slices.wav"));
	var loader = FluidLoadFolder(FluidFilesPath());
	loader.play(s);
	defer{
		FluidPlotter(dict:dict,mouseMoveAction:{
			arg view, x, y;
			xybuf.setn(0,[x,y]);
			tree.kNearest(xybuf,1,action:{
				arg id;
				var index = id.asInteger;
				defer{
					view.highlight_(id);
				};
				
				{
					var start = Index.kr(slicePoints,index);
					var end = Index.kr(slicePoints,index+1);
					var sig = PlayBuf.ar(2,loader.buffer,BufRateScale.ir(loader.buffer),1,start)[0];
					var dur_sec = min((end-start) / SampleRate.ir,1);
					var env = EnvGen.kr(Env([0,1,1,0],[0.03,dur_sec-0.06,0.03]),doneAction:2);
					sig.dup * env;
				}.play;
			});
		});
	};
});
)

::
strong::radius and num neighbours::
code::

// set some initial values
(
~numNeighbours = 3;
~tree.radius_(0.04);
)


// then make the plot, once it's up and you're clicking around,
// change the numbers and re-run the code above to see the differences
(
var ds = FluidDataSet(s).load(
	Dictionary.newFrom([
		"cols",2,
		"data",Dictionary.newFrom(
			100.collect{
				arg i;
				[i,{rrand(0.0,1.0)}!2]
			}.flatten
		)
	])
);
~tree = FluidKDTree(s).fit(ds);
ds.dump({
	arg dict;
	var xybuf = Buffer.alloc(s,2);
	defer{
		FluidPlotter(dict:dict,mouseMoveAction:{
			arg view, x, y;
			xybuf.setn(0,[x,y]);
			~tree.kNearest(xybuf,~numNeighbours,{
				arg id;
				defer{
					view.highlight_(id);
				};
			});
		});
	};
});
)
::

subsection:: Queries in a Synth

Input and output is done via buffers, which will need to be preallocated to the correct sizes:
LIST::
##Your input buffer should be sized to the input data dimension (2, in this example)
##Your output buffer should be the number of neighbours * output dimensionality
::

We can't simply return labels (i.e. strings) from a UGen, so the query returns the actual data points from a DataSet instead. By default, this is the FluidDataSet against which the tree was fitted. However, by passing a different dataset to code::kr::'s code::lookupDataSet:: argument instead, you can return different points, so long as the labels in the two datasets match. In this way, the FluidKDTree can be used to perform nearest neighbour mappings in a synth.

For instance, whilst fitting the tree against some n-dimensional descriptor data, our lookup dataset could use the same labels to map descriptor entries back to buffers, or locations in buffers, so that queries can be used to trigger audio.

code::

~src = Buffer.read(s,FluidFilesPath("Constanzo-PreparedSnare-M.wav"));

// create two datasets:
// one of mfcc analyses for each slice and one of the playback information for each slice
(
var indices = Buffer(s);
var mfccs = Buffer(s);
var stats = Buffer(s);
var flat = Buffer(s);
var playback_info_dict = Dictionary.newFrom([
	"cols",2,
	"data",Dictionary.new;
]);

~ds_mfccs = FluidDataSet(s);

FluidBufOnsetSlice.processBlocking(s,~src,indices:indices,metric:9,threshold:0.7);
indices.loadToFloatArray(action:{
	arg fa;

	// go through each slice (from one slice point to the next)
	fa.doAdjacentPairs{
		arg start, end, i;
		var num = end - start;
		var id = "slice-%".format(i);

		// add playback info for this slice to this dict
		playback_info_dict["data"][id] = [start,num];

		FluidBufMFCC.processBlocking(s,~src,start,num,startCoeff:1,features:mfccs);
		FluidBufStats.processBlocking(s,mfccs,stats:stats,select:[\mean]);
		FluidBufFlatten.processBlocking(s,stats,destination:flat);

		// add analysis info for this slice to this data set
		~ds_mfccs.addPoint(id,flat);
	};

	~ds_playback = FluidDataSet(s).load(playback_info_dict);

	~ds_mfccs.print;
	~ds_playback.print;
});
)

// we'll use this kdtree to find the nearest neighbour in 13 dimensions (mfccs)
~tree = FluidKDTree(s);

~tree.fit(~ds_mfccs);

// of course it will often find "itself" because the source and lookup sounds are the same.
// try with different source and lookup sounds
(
{
	var src = PlayBuf.ar(1,~src,BufRateScale.ir(~src),loop:1);
	var mfccs = FluidMFCC.kr(src,startCoeff:1);
	var mfccbuf = LocalBuf(mfccs.numChannels);
	var playbackinfo = LocalBuf(2);
	var trig = Impulse.kr(10); // could change how often the lookup happens...
	var start, num, sig_looked_up;

	FluidKrToBuf.kr(mfccs,mfccbuf);

	// kdtree finding the nearest neighbour in 13 dimensions
	~tree.kr(trig,mfccbuf,playbackinfo,1,~ds_playback);
	# start, num = FluidBufToKr.kr(playbackinfo);

	start.poll(label:"start frame");
	num.poll(label:"num frames");

	// not using num frames for playback here, but one certainly could!
	sig_looked_up = PlayBuf.ar(1,~src,BufRateScale.ir(~src),trig,start);
	[src,sig_looked_up * -7.dbamp];
}.play;
)
::