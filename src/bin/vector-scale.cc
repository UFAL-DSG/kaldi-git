// bin/vector-scale.cc

// Copyright 2009-2011  Microsoft Corporation
//                2014  Johns Hopkins University (author: Daniel Povey)

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "matrix/kaldi-matrix.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Scale a set of vectors in a Table (useful for speaker vectors and "
        "per-frame weights)\n"
        "Usage: vector-scale [options] <in-rspecifier|in-rxfilename> "
        "<out-wspecifier|out-wxfilename>\n";

    bool binary = true;
    BaseFloat scale = 1.0;
    BaseFloat inverse_scale = 0.0;

    ParseOptions po(usage);

    po.Register("binary", &binary, "If true, write output as binary (only "
                "relevant for non-table input-output");
    po.Register("scale", &scale, "Scaling factor for vectors");
    po.Register("inverse-scale", &inverse_scale, "Inverse scaling factor for vectors; "
        "--scale option will be ignored if this is given and is non-zero");
    po.Read(argc, argv);

    if (inverse_scale != 0.0) {
      scale = 1.0/inverse_scale;
    }

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    if (ClassifyRspecifier(po.GetArg(1), NULL, NULL) != kNoRspecifier) {
      if (ClassifyRspecifier(po.GetArg(2), NULL, NULL) == kNoRspecifier) {
        KALDI_ERR << "Cannot mix table and non-table arguments";
      }

      // outputs to table
      std::string rspecifier = po.GetArg(1);
      std::string wspecifier = po.GetArg(2);

      BaseFloatVectorWriter vec_writer(wspecifier);

      SequentialBaseFloatVectorReader vec_reader(rspecifier);

      int32 num_done = 0;
      for (; !vec_reader.Done(); vec_reader.Next(), num_done++) {
        Vector<BaseFloat> vec(vec_reader.Value());
        vec.Scale(scale);
        vec_writer.Write(vec_reader.Key(), vec);
      }

      KALDI_LOG << "Scaled " << num_done << " vectors in " << rspecifier 
                << "and wrote to " << wspecifier;

      return (num_done > 0);
    }
    
    if (ClassifyRspecifier(po.GetArg(2), NULL, NULL) != kNoRspecifier) {
      KALDI_ERR << "Cannot mix table and non-table arguments";
    }

    std::string rx_filename = po.GetArg(1);
    std::string wx_filename = po.GetArg(2);

    bool binary_in;
    Input ki(rx_filename, &binary_in);

    Vector<BaseFloat> vec;
    vec.Read(ki.Stream(), binary_in);
    vec.Scale(scale);

    WriteKaldiObject(vec, wx_filename, binary);
    KALDI_LOG << "Scaled vector in " << rx_filename
      << "and wrote to " << wx_filename;

  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


