import os, subprocess, sys, json
H=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,H)
from iss import ISS, read_hex
d=f'{H}/systests/m_intdiv'; it, dt = read_hex(f'{d}/ITCM.h',2048), read_hex(f'{d}/DTCM.h',2048)
iss = ISS(it, dt, mul16=True, io=lambda op,a,v: (a & 0x3FFF) >= 0x2000 if op=='is' else 0); iss.run()
exp_s4, exp_t1 = iss.dmem[8], iss.dmem[11]
res={}
PRESSES=[300+41*k for k in range(int(os.environ.get("NPRESS","5")))]
for v in sys.argv[1:]:
    run=f'{H}/runs/sys_{v}/m_intdiv'; os.makedirs(run, exist_ok=True)
    for f in ('ITCM.h','DTCM.h'): open(f'{run}/{f}','w').write(open(f'{d}/{f}').read())
    presses=PRESSES
    open(f'{run}/stim.txt','w').write(''.join(f'{c} KEY 1 0\n{c+3} KEY 1 1\n' for c in presses))
    subprocess.run(['ghdl','-r','--std=08','-fsynopsys','-frelaxed',f'-P{H}/simlib',f'--workdir={H}/{v}','tb_mcu','-gMAXCYC=4000','--ieee-asserts=disable'],cwd=run,capture_output=True)
    out=read_hex(f'{run}/dtcm_out.h',2048)
    a0=[int(l.split()[3],16) for l in open(f'{run}/commits.log') if l.startswith('R ') and l.split()[2]=='10']
    out[10]=a0[-1] if a0 else 0   # final ISR count from the register trace (store may precede late ISRs)
    cyc=[l.split() for l in open(f'{run}/cycles.log')]
    deferred=sum(1 for t in cyc if t[2][0]=='1' and t[2][3]=='1')
    svc=sum(1 for l in open(f'{run}/commits.log') if l.startswith('O') and l.split()[2]=='4')
    ok = out[8]==exp_s4 and out[11]==exp_t1 and out[10]==len(presses) and svc==len(presses) and deferred>0
    res[v]=dict(PASS=ok, deferred_cycles=deferred, services=svc, isr_count=out[10])
    print(v, 'PASS' if ok else 'FAIL', f"s4={out[8]:#x} (golden {exp_s4:#x}) quotient={out[11]:#x} (golden {exp_t1:#x}) ISR count={out[10]}/{len(presses)} services={svc} reti={sum(1 for l in open(f'{run}/commits.log') if l.startswith('O') and l.split()[2]=='3' and l.split()[3]=='00000001')} request-while-div-busy cycles={deferred}")
json.dump(res, open(f'{H}/results_sys_intdiv.json','w'))
