// Asset self-check for xmas.xpk. Build + run on any machine / CI runner:
//   clang++ -std=c++17 -Isrc tools/verify_assets.cpp src/AssetManager.cpp src/TextureLoader.cpp \
//       src/ElementCatalog.cpp src/LevelParser.cpp src/AniParser.cpp src/XFileParser.cpp -lz -o verify_assets
//   ./verify_assets assets/xmas.xpk
// Exit code is 1 if a catalog mesh is missing, a level object has no TYPE, or a texture fails to decode.
#include "AssetManager.h"
#include "TextureLoader.h"
#include "ElementCatalog.h"
#include "LevelParser.h"
#include "AniParser.h"
#include <cstdio>
#include <cstring>
#include <set>
#include <map>
int main(int argc,char**argv){
  AssetManager am; if(!am.loadXPK(argc>1?argv[1]:"assets/xmas.xpk")) { printf("cannot open xpk\n"); return 1; }
  auto names=am.getAllFilenames();
  // 1. case-insensitive lookups
  printf("hasAsset('gfx\\\\Snow_Corner.X')=%d  ('gfx/platt_T.x')=%d  ('GFX\\\\WEIHNACHTSMAN_000.X')=%d\n",
     am.hasAsset("gfx\\Snow_Corner.X"),am.hasAsset("gfx/platt_T.x"),am.hasAsset("GFX\\WEIHNACHTSMAN_000.X"));
  // 2. catalog
  auto raw=am.getAssetData("data\\elements.txt"); std::string txt(raw.begin(),raw.end());
  ElementCatalog& cat=ElementCatalog::shared(); size_t n=cat.parse(txt);
  int missing=0; std::map<std::string,int> types;
  for(auto&d:cat.all()){ types[d.type]++; if(!am.hasAsset(d.meshFile)){missing++; printf("  MISSING mesh for %s -> %s\n",d.name.c_str(),d.meshFile.c_str());} }
  printf("catalog: %zu elements, meshFile missing in XPK: %d\n",n,missing);
  for(auto&t:types) printf("   %-14s %d\n",t.first.c_str(),t.second);
  // 3. levels
  int total=0,unk=0; std::map<std::string,int> lt;
  for(auto&f:names){ if(f.find("levels\\")!=0) continue; auto d=am.getAssetData(f); auto L=LevelParser::parse(d.data(),d.size());
    total+=L.entities.size(); for(auto&e:L.entities){ auto t=LevelParser::getEntityType(e.name); lt[t]++; if(t=="UNKNOWN")unk++; } }
  printf("levels: %d objects, UNKNOWN type: %d\n",total,unk); for(auto&t:lt) printf("   %-14s %d\n",t.first.c_str(),t.second);
  // 4. all textures decode
  int ok=0,bad=0;
  for(auto&f:names){ if(f.find("maps\\")!=0) continue; std::string ext=f.substr(f.size()-4); if(ext==".jpg") continue;
    auto d=am.getAssetData(f); std::vector<uint8_t> rgba; int w,h; if(TextureLoader::decodeImage(d,rgba,w,h)){ok++;} else {bad++; printf("  DECODE FAIL %s\n",f.c_str());} }
  printf("textures decoded: %d ok, %d failed (jpg skipped)\n",ok,bad);
  // 5. every texture ref used by the 88 .x resolves to a real file
  const char* refs[]={"D:\\Firma\\x\\Nicolaus.bmp","D:\\a\\Rabe.bmp","D:\\a\\Schneemann.bmp","D:\\a\\WinterTroll.bmp","D:\\a\\haus2.tga","D:\\a\\misc.tga","D:\\a\\objects.tga","D:\\a\\dach.jpg","D:\\a\\objects_old.jpg","D:\\a\\qmeter.jpg","D:\\a\\himmel.tga","D:\\a\\#tanne.tga","D:\\a\\dachpeter.tga","gui2.tga"};
  for(auto r:refs){ auto p=TextureLoader::resolveTextureXPKPath(r); printf("   %-28s -> %-24s %s\n",r,p.c_str(),am.hasAsset(p)?"OK":"MISSING"); }
  // 6. .ani decompress is passthrough
  auto ani=am.getAssetData("gfx\\weihnachtsman_000.ani"); auto out=AniParser::decompress(ani.data(),ani.size());
  int fail=(missing>0)||(unk>0)||(bad>0);
  printf(".ani passthrough: in=%zu out=%zu\n",ani.size(),out.size());
  return fail;
}
