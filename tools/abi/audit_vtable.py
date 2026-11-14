"""Verify every compiled AWDL subclass virtual slot against the native table of its macOS version.

Usage: python3 tools/abi/audit_vtable.py [--target tahoe|sequoia|sonoma] --build <dir> --lifecycle-overrides
  tahoe:   native-vtables.json, read from the running 26.7.1 (25G241) kernel collection
  sequoia: native-vtables-24H241.json, from the 15.8.3 Kernel Debug Kit (15.8's table is identical)
  sonoma:  native-vtables-23J631.json, from the 14.8.9 Kernel Debug Kit
Slots 0x90 (free) and 0x5c8 (stop) differ by design; --lifecycle-overrides accepts them.
The #13 diagnostics also override handleOpen, handleClose, prepareBSDInterface and finalizeBSDInterface;
a slot is accepted when the driver's method has the native method's exact mangled name and signature."""
import argparse,json,re,struct
from pathlib import Path
root=Path(__file__).parent
parser=argparse.ArgumentParser()
parser.add_argument('--build',type=Path,default=root.parents[1]/'build')
parser.add_argument('--out',type=Path,default=root.parents[1]/'build')
parser.add_argument('--lifecycle-overrides',action='store_true')
parser.add_argument('--target',choices=('tahoe','sequoia','sonoma'),default='tahoe')
args=parser.parse_args()
object_path=next((args.build/'obj').glob('AirportItlwmV2-*.o'))
raw=object_path.read_bytes()
sections=[]
p=32
for _ in range(struct.unpack_from('<I',raw,16)[0]):
    cmd,size=struct.unpack_from('<II',raw,p)
    if cmd==0x19:
        for i in range(struct.unpack_from('<I',raw,p+64)[0]):
            q=p+72+i*80
            addr,length,offset,align,reloff,nreloc=struct.unpack_from('<QQIIII',raw,q+32)
            sections.append(dict(addr=addr,length=length,offset=offset,reloff=reloff,nreloc=nreloc))
    if cmd==2:so,n,st,sz=struct.unpack_from('<IIII',raw,p+8)
    p+=size
symbols=[]
for i in range(n):
    si,nt,sec,desc,value=struct.unpack_from('<IBBHQ',raw,so+i*16)
    name=raw[st+si:raw.find(b'\0',st+si,st+sz)].decode()
    symbols.append(dict(name=name,value=value,section=sec))
symbol=next(x for x in symbols if x['name']=='__ZTV16ItlAWDLInterface')
section=sections[symbol['section']-1]
relocations={}
for i in range(section['nreloc']):
    addr,info=struct.unpack_from('<II',raw,section['reloff']+i*8)
    assert not addr & 0x80000000
    if (info>>27)&1:
        relocations[addr]=symbols[info&0xffffff]['name']
    else:
        value=struct.unpack_from('<Q',raw,section['offset']+addr)[0]
        candidates=[s['name'] for s in symbols if s['section'] and s['value']==value]
        assert candidates,(hex(addr),hex(value))
        relocations[addr]=candidates[0]
tables=json.loads((root/{'tahoe':'native-vtables.json','sequoia':'native-vtables-24H241.json','sonoma':'native-vtables-23J631.json'}[args.target]).read_text())
native=tables['IO80211AWDLProtocol']['entries'][:]
while native and int(native[-1]['packed'],16)==0:native.pop()
concrete=tables['AppleBCMWLANProximityInterface']['entries']
results=[]
for i,e in enumerate(native):
    assert e['symbols'],e
    expected=e['symbols'][0]
    if expected=='___cxa_pure_virtual':
        expected=concrete[i]['symbols'][0].replace('__ZN30AppleBCMWLANProximityInterface','__ZN16ItlAWDLInterface')
    elif e['slot'] in (0,8):
        expected=expected.replace('__ZN19IO80211AWDLProtocol','__ZN16ItlAWDLInterface')
    elif e['slot']==0x38:
        expected=expected.replace('__ZNK19IO80211AWDLProtocol','__ZNK16ItlAWDLInterface')
    elif args.lifecycle_overrides and e['slot'] in (0x90,0x5c8):
        expected=expected.replace('__ZN23IO80211VirtualInterface','__ZN16ItlAWDLInterface')
    offset=symbol['value']-section['addr']+16+e['slot']
    actual=relocations.get(offset)
    method=re.match(r'__ZNK?\d+([A-Za-z0-9_]+?)(\d+(?:handleOpen|handleClose|prepareBSDInterface|finalizeBSDInterface)E.*)$',expected)
    if method and actual and actual.startswith('__ZN16ItlAWDLInterface') and actual.endswith(method.group(2)):
        expected=actual
    results.append(dict(slot=hex(e['slot']),expected=expected,actual=actual,match=actual==expected))
failures=[x for x in results if not x['match']]
controller=next(x for x in symbols if x['name']=='__ZTV12AirportItlwm')
assert controller['section']==symbol['section']
# The controller slot macOS calls to create awdl0: 0xdd8 on Tahoe and Sequoia, 0xe00 on Sonoma (23J631).
factory_slot={'tahoe':0xdd8,'sequoia':0xdd8,'sonoma':0xe00}[args.target]
factory=relocations[controller['value']-section['addr']+16+factory_slot]
assert factory=='__ZN12AirportItlwm22createVirtualInterfaceEP10ether_addrj',factory
report=dict(target=args.target,object=str(object_path),controller_factory_slot=hex(factory_slot),controller_factory=factory,slots=len(results),matches=len(results)-len(failures),failures=failures,entries=results)
(args.out/'compiled-vtable-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ('target','slots','matches','failures')},indent=2))
assert not failures
