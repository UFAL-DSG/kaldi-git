#!/bin/bash
# Copyright 2010-2012 Microsoft Corporation  Arnab Ghoshal  Daniel Povey
# Apache 2.0


# To be run from ..
# Flat start and monophone training, with delta-delta features.
# This script applies cepstral mean normalization (per speaker).

nj=4
cmd=scripts/run.pl
for x in 1 2; do
  if [ $1 == "--num-jobs" ]; then
    nj=$2
    shift 2
  fi
  if [ $1 == "--cmd" ]; then
    cmd=$2
    shift 2
  fi  
done

if [ $# != 3 ]; then
   echo "Usage: steps/train_mono.sh <data-dir> <lang-dir> <exp-dir>"
   echo " e.g.: steps/train_mono.sh data/train.1k data/lang exp/mono"
   exit 1;
fi

data=$1
lang=$2
dir=$3

if [ -f path.sh ]; then . path.sh; fi

# Configuration:
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
numiters=40    # Number of iterations of training
maxiterinc=30 # Last iter to increase #Gauss on.
numgauss=300 # Initial num-Gauss (must be more than #states=3*phones).
totgauss=1000 # Target #Gaussians.  
incgauss=$[($totgauss-$numgauss)/$maxiterinc] # per-iter increment for #Gauss
realign_iters="1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 23 26 29 32 35 38";
oov_sym=`cat $lang/oov.txt`
sdata=$data/split$nj;                   

mkdir -p $dir/log
if [ ! -d $sdata -o $sdata -ot $data/feats.scp ]; then
  split_data.sh $data $nj
fi



feats="ark:apply-cmvn --norm-vars=false --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | add-deltas ark:- ark:- |"
example_feats="`echo '$feats' | sed s/JOB/1/g`";

echo "Initializing monophone system."

if [ -f $lang/phones/sets_mono.int ]; then
  shared_phones_opt="--shared-phones=$lang/phones/sets_mono.int"
fi

# Note: JOB=1 just uses the 1st part of the features-- we only need a subset anyway.
! $cmd JOB=1 $dir/log/init.log \
 gmm-init-mono $shared_phones_opt "--train-feats=$feats subset-feats --n=10 ark:- ark:-|" $lang/topo 39 \
   $dir/0.mdl $dir/tree && echo "Error initializing monophone" && exit 1;

rm $dir/.error 2>/dev/null

echo "Compiling training graphs"
$cmd JOB=1:$nj $dir/log/compile_graphs.JOB.log \
  compile-train-graphs $dir/tree $dir/0.mdl  $lang/L.fst \
   "ark:sym2int.pl --map-oov '$oov_sym' --ignore-first-field $lang/words.txt < $sdata/JOB/text|" \
    "ark:|gzip -c >$dir/JOB.fsts.gz" || exit 1;

echo "Aligning data equally (pass 0)"
$cmd JOB=1:$nj $dir/log/align.0.JOB.log \
  align-equal-compiled "ark:gunzip -c $dir/JOB.fsts.gz|" "$feats" ark,t:-  \| \
    gmm-acc-stats-ali --binary=true $dir/0.mdl "$feats" ark:- \
      $dir/0.JOB.acc || exit 1;


# In the following steps, the --min-gaussian-occupancy=3 option is important, otherwise
# we fail to est "rare" phones and later on, they never align properly.

gmm-est --min-gaussian-occupancy=3  --mix-up=$numgauss \
  $dir/0.mdl "gmm-sum-accs - $dir/0.*.acc|" $dir/1.mdl 2> $dir/log/update.0.log || exit 1;

rm $dir/0.*.acc

beam=6 # will change to 10 below after 1st pass
# note: using slightly wider beams for WSJ vs. RM.
x=1
while [ $x -lt $numiters ]; do
  echo "Pass $x"
  if echo $realign_iters | grep -w $x >/dev/null; then
    echo "Aligning data"
    $cmd JOB=1:$nj $dir/log/align.$x.JOB.log \
      gmm-align-compiled $scale_opts --beam=$beam --retry-beam=$[$beam*4] $dir/$x.mdl \
        "ark:gunzip -c $dir/JOB.fsts.gz|" "$feats" "ark,t:|gzip -c >$dir/JOB.ali.gz" \
       || exit 1;
  fi
  $cmd JOB=1:$nj $dir/log/acc.$x.JOB.log \
    gmm-acc-stats-ali  $dir/$x.mdl "$feats" "ark:gunzip -c $dir/JOB.ali.gz|" \
      $dir/$x.JOB.acc || exit 1;

  $cmd $dir/log/update.$x.log \
    gmm-est --write-occs=$dir/$[$x+1].occs --mix-up=$numgauss $dir/$x.mdl \
      "gmm-sum-accs - $dir/$x.*.acc|" $dir/$[$x+1].mdl || exit 1;
  rm $dir/$x.mdl $dir/$x.*.acc $dir/$x.occs 2>/dev/null
  if [ $x -le $maxiterinc ]; then
     numgauss=$[$numgauss+$incgauss];
  fi
  beam=10
  x=$[$x+1]
done

( cd $dir; rm final.{mdl,occs} 2>/dev/null; ln -s $x.mdl final.mdl; ln -s $x.occs final.occs )

# Print out summary of the warning messages.
for x in $dir/log/*.log; do 
  n=`grep WARNING $x | wc -l`; 
  if [ $n -ne 0 ]; then echo $n warnings in $x; fi; 
done

echo Done

# example of showing the alignments:
# show-alignments data/lang/phones.txt $dir/30.mdl "ark:gunzip -c $dir/0.ali.gz|" | head -4
