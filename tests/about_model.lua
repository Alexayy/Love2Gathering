-- Bounded build provenance and fixed credit links, without OS/network actions.
package.path='./?.lua;'..package.path
local json=require('lib.json');local Build=require('app.build_info')
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('ABOUT MODEL PASS '..label)end
local valid={version='2026.11.16.42',channel='development',branch='development',revision=string.rep('a',40),tag='DEV-2026.11.16.42-1-aaaaaaaaaaaa',builtAtUTC='2026-11-16T09:12:34Z',repository=Build.repository,engineRevision=string.rep('b',40)}
local info=Build.load({readManifest=function()return json.encode(valid)end,readStatus=function()error('Packaged metadata must not read launcher status')end})
check(info.packaged and info.version==valid.version and info.channel=='development'and info.revision==valid.revision and info.engineRevision==valid.engineRevision,'Packaged build information preserves its actual version/channel/revisions')
check(Build.summary(info):find(valid.tag,1,true)and Build.summary(info):find(valid.builtAtUTC,1,true),'Copyable build details retain the release tag and UTC timestamp')
local localBuild=json.decode(json.encode(valid));localBuild.channel='source';localBuild.version='2026.11.14'
check(Build.decode(json.encode(localBuild)).version=='2026.11.14','A locally packaged source build retains its legacy three-part version')
localBuild.channel='stable';check(not Build.decode(json.encode(localBuild)),'Release channels still require the four-part version format')
local source=Build.load({readManifest=function()return nil end,readStatus=function()return{version='724032c'}end})
check(not source.packaged and not source.version and source.channel=='source'and source.revision=='724032c','A source checkout uses its real launcher revision without inventing a release version')
check(Build.lines(source)[1].value=='Source build','Source fallback is visibly labeled Source build')
for _,version in ipairs({'local build','2026.11.16.1','not-a-revision',string.rep('a',41)})do
 local value=Build.load({readManifest=function()return'{'end,readStatus=function()return{version=version}end})
 check(not value.revision and not value.version,'A launcher label is not fabricated as a commit: '..version:sub(1,24))
end
local invalid=json.decode(json.encode(valid));invalid.channel='nightly-made-up';check(not Build.decode(json.encode(invalid)),'Unknown build channels cannot masquerade as development or stable')
invalid=json.decode(json.encode(valid));invalid.revision='abc1234';check(not Build.decode(json.encode(invalid)),'Packaged revision requires the full source SHA')
check(not Build.decode(string.rep(' ',Build.maxBytes+1))and not Build.decode('[]'),'Oversized and non-build JSON are rejected within the read bound')
invalid=json.decode(json.encode(valid));invalid.branch='development\nspoofed';invalid.tag=string.rep('x',129);invalid.builtAtUTC='2026-11-16T09:12:34123Z';invalid.repository='https://unapproved.invalid'
local cleaned=Build.decode(json.encode(invalid))
check(cleaned and not cleaned.branch and not cleaned.tag and not cleaned.builtAtUTC and not cleaned.repository,'Malformed optional build text/URLs cannot add fake display lines or links')
local files={LICENSE={body='MIT License\nCopyright test\nPermission text.',size=45},['large.txt']={body='too large',size=129*1024}}
local opened={};love={filesystem={getInfo=function(path)local file=files[path];return file and{size=file.size}end,read=function(path)return files[path]and files[path].body end},system={openURL=function(url)opened[#opened+1]=url;return true end}}
package.preload['app.credits']=function()
 return{links={{label='Project',url=Build.repository}},sections={{items={{name='Engine',links={{label='XMage',url='https://github.com/magefree/mage'}}}}}}}
end
local About=require('app.about')
check(About.readLicense('LICENSE')==files.LICENSE.body,'License text is readable offline from the application VFS')
check(not About.readLicense('../secret')and not About.readLicense('/home/test/private')and not About.readLicense('C:\\private'),'The notice reader rejects absolute and traversal paths')
check(not About.readLicense('large.txt')and not About.readLicense('missing.txt'),'Oversized or absent notices produce an explicit unavailable result')
check(About.openLink(Build.repository)and About.openLink('https://github.com/magefree/mage')and#opened==2,'Only user-selected links in verified credit data reach the browser')
check(not About.openLink('https://unapproved.invalid')and not About.openLink('file:///tmp/test')and not About.openLink(Build.repository..'\n')and#opened==2,'Unlisted URLs and non-web targets never reach the browser')
print('About model checks: '..checks)
