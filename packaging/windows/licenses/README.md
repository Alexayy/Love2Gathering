# Software OpenGL notices and provenance

The Windows package distributes only the statically linked `opengl32.dll` from
[mmozeiko/build-mesa 26.3.0](https://github.com/mmozeiko/build-mesa/releases/tag/26.3.0),
not a system driver installer. That repository's versioned build script records
Mesa 26.3.0 and LLVM 23.1.5. The binary archive URL and SHA256 are fixed in
`../runtimes.lock.json` and copied into Windows runtime provenance.

* Binary archive: `mesa-llvmpipe-x64-26.3.0.7z`
* Archive SHA256: `11dc079e356f33ce2ff84aa399c975da1a7bdd4c470f6eef4cf359ad8b9ca80f`
* Mesa source: https://archive.mesa3d.org/mesa-26.3.0.tar.xz
* Mesa source SHA256: `91d729aa68bb89e4ec857841300bbe922bcb3e52b1f97566ca83930d3b28343a`
* Build recipe: https://github.com/mmozeiko/build-mesa/blob/26.3.0/build.cmd
* LLVM license: https://github.com/llvm/llvm-project/blob/llvmorg-23.1.5/llvm/LICENSE.TXT
* zlib fallback: https://github.com/madler/zlib/blob/v1.3.1/LICENSE
* Expat fallback: https://github.com/libexpat/libexpat/blob/R_2_5_0/expat/COPYING

The upstream binary archive contains no notice files. These accompanying files
retain the original Mesa license guide, permissive SPDX license texts and
copyright/permission comment blocks collected from that exact Mesa source
archive, together with the LLVM and optional static dependency notices. The
source/archive downloads stay in the ignored build cache. No library code is
modified, and these component licenses remain separate from the application's MIT.
