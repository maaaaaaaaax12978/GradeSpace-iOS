/* A touch-driven liquid selection lens. No timers or frames run while idle. */
(()=>{
'use strict';
class LiquidTabBar {
    constructor(bar) {
        this.bar=bar;
        this.buttons=Array.from(bar.querySelectorAll('button[data-page]'));
        if(this.buttons.length!==4)return;
        this.lens=document.createElement('span');
        this.lens.className='tabbar-lens';
        this.lens.setAttribute('aria-hidden','true');
        this.lens.innerHTML='<span class="tabbar-lens-shine"></span>';
        bar.prepend(this.lens);
        bar.classList.add('interactive-tabbar');
        this.motion=matchMedia('(prefers-reduced-motion: reduce)');
        this.selected=Math.max(0,this.buttons.findIndex(b=>b.dataset.page===bar.dataset.page));
        this.preview=this.selected;
        this.x=0;this.vx=0;this.target=0;this.y=0;this.vy=0;this.targetY=0;
        this.press=0;this.bounce=0;this.pointer=null;this.frame=0;this.lastTime=0;
        this.slot=0;this.inset=8;this.suppressUntil=0;this.hapticTime=0;
        bar.addEventListener('pointerdown',e=>this.down(e));
        bar.addEventListener('pointermove',e=>this.move(e));
        bar.addEventListener('pointerup',e=>this.end(e,false));
        bar.addEventListener('pointercancel',e=>this.end(e,true));
        bar.addEventListener('lostpointercapture',e=>this.end(e,true));
        bar.addEventListener('click',e=>{
            if(e.detail!==0&&performance.now()<this.suppressUntil){e.preventDefault();e.stopImmediatePropagation()}
        },true);
        bar.addEventListener('contextmenu',e=>e.preventDefault());
        window.addEventListener('blur',()=>this.cancel());
        document.addEventListener('visibilitychange',()=>{if(document.hidden)this.cancel()});
        this.motion.addEventListener('change',()=>{if(this.motion.matches)this.snap();else this.wake()});
        if(typeof ResizeObserver!=='undefined'){
            this.observer=new ResizeObserver(()=>this.measure());this.observer.observe(bar);
        }else window.addEventListener('resize',()=>this.measure());
        this.measure(true);
    }
    measure(initial=false){
        const r=this.bar.getBoundingClientRect();
        if(!r.width||!this.bar.offsetWidth)return;
        const scale=r.width/this.bar.offsetWidth,b=this.buttons[0].getBoundingClientRect();
        const oldSlot=this.slot;
        this.slot=b.width/scale;
        this.inset=(b.left-r.left)/scale;
        if(!this.slot)return;
        this.lens.style.left=this.inset+'px';this.lens.style.width=this.slot+'px';
        if(this.pointer!==null)this.cancel();
        this.target=this.selected*this.slot;
        this.x=initial||!oldSlot?this.target:this.x*this.slot/oldSlot;
        this.vx=0;this.paint();this.wake();
    }
    localX(clientX){const r=this.bar.getBoundingClientRect();return (clientX-r.left)/(r.width/this.bar.offsetWidth)-this.inset}
    indexAt(clientX){return Math.max(0,Math.min(3,Math.floor(this.localX(clientX)/this.slot)))}
    fingerTarget(clientX){const raw=this.localX(clientX)-this.slot/2,max=this.slot*3;return raw<0?-Math.min(12,-raw*.18):raw>max?max+Math.min(12,(raw-max)*.18):raw}
    sync(page){
        const next=this.buttons.findIndex(b=>b.dataset.page===page);
        if(next<0)return;
        const changed=next!==this.selected;
        this.selected=next;
        if(this.pointer===null){this.preview=next;this.target=next*this.slot;this.targetY=0;if(changed)this.bounce=1;this.wake()}
    }
    down(e){
        if(e.isPrimary===false||this.pointer!==null||e.button>0||!this.slot)return;
        e.preventDefault();
        this.pointer=e.pointerId;this.startX=e.clientX;this.startY=e.clientY;
        this.preview=this.indexAt(e.clientX);this.target=this.fingerTarget(e.clientX);this.targetY=0;
        this.bar.classList.add('is-scrubbing');
        this.suppressUntil=performance.now()+800;
        try{this.bar.setPointerCapture(e.pointerId)}catch{}
        this.wake();
    }
    move(e){
        if(e.pointerId!==this.pointer)return;
        e.preventDefault();
        this.target=this.fingerTarget(e.clientX);
        this.targetY=Math.max(-4,Math.min(4,(e.clientY-this.startY)*.1));
        const next=this.indexAt(e.clientX);
        if(next!==this.preview){this.preview=next;this.haptic()}
        this.wake();
    }
    end(e,cancelled){
        if(this.pointer===null||e.pointerId!==this.pointer)return;
        if(!cancelled&&Number.isFinite(e.clientX)){this.preview=this.indexAt(e.clientX);this.target=this.fingerTarget(e.clientX)}
        const next=cancelled?this.selected:this.preview,id=this.pointer;
        this.pointer=null;this.preview=next;this.target=next*this.slot;this.targetY=0;this.bounce=cancelled?0:1;
        this.bar.classList.remove('is-scrubbing');
        this.suppressUntil=performance.now()+600;
        try{if(this.bar.hasPointerCapture(id))this.bar.releasePointerCapture(id)}catch{}
        if(!cancelled&&next!==this.selected){this.haptic();go(this.buttons[next].dataset.page)}
        this.wake();
    }
    cancel(){if(this.pointer!==null)this.end({pointerId:this.pointer},true)}
    haptic(){
        const now=performance.now();if(now-this.hapticTime<60)return;this.hapticTime=now;
        if(window.__afterBellNative)window.webkit?.messageHandlers?.tabHaptic?.postMessage({kind:'selection'});
    }
    snap(){
        if(this.frame)cancelAnimationFrame(this.frame);
        this.frame=0;this.lastTime=0;this.x=this.target;this.y=this.targetY;this.vx=0;this.vy=0;this.press=0;this.bounce=0;this.paint();
    }
    wake(){
        if(this.motion.matches){this.snap();return}
        if(!this.frame){this.lastTime=0;this.frame=requestAnimationFrame(t=>this.step(t))}
    }
    step(time){
        this.frame=0;
        const dt=this.lastTime?Math.min(1/30,Math.max(1/240,(time-this.lastTime)/1000)):1/60;
        this.lastTime=time;
        const pressed=this.pointer!==null,k=pressed?900:520,damping=pressed?50:34;
        // Substeps keep the glass spring stable even when frames fall to 30 FPS.
        const steps=Math.ceil(dt*120),h=dt/steps;
        for(let i=0;i<steps;i++){
            this.vx+=((this.target-this.x)*k-this.vx*damping)*h;this.x+=this.vx*h;
            this.vy+=((this.targetY-this.y)*500-this.vy*35)*h;this.y+=this.vy*h;
        }
        this.press+=((pressed?1:0)-this.press)*(1-Math.exp(-dt*22));
        this.bounce*=Math.exp(-dt*7);
        const moving=Math.abs(this.target-this.x)>.035||Math.abs(this.vx)>.08||Math.abs(this.targetY-this.y)>.02||Math.abs(this.vy)>.08||Math.abs((pressed?1:0)-this.press)>.002||this.bounce>.002;
        if(!moving){this.x=this.target;this.y=this.targetY;this.press=pressed?1:0;this.vx=0;this.vy=0;this.bounce=0;this.lastTime=0}
        this.paint();
        if(moving)this.frame=requestAnimationFrame(t=>this.step(t));
    }
    paint(){
        if(!this.slot)return;
        const reduced=this.motion.matches;
        const stretch=reduced?0:Math.min(.27,Math.abs(this.vx)/3000),press=reduced?0:this.press;
        const sx=1+stretch+press*.055,sy=1-stretch*.23+press*.025;
        this.lens.style.transform=`translate3d(${this.x.toFixed(3)}px,${(this.y-press*1.5).toFixed(3)}px,0) scale(${sx.toFixed(4)},${sy.toFixed(4)})`;
        this.lens.style.setProperty('--lens-glow',String(.32+press*.35));
        this.lens.style.setProperty('--lens-shine',`${50+Math.max(-25,Math.min(25,this.vx/45))}%`);
        this.buttons.forEach((b,i)=>{
            const proximity=Math.max(0,1-Math.abs(i*this.slot-this.x)/this.slot);
            const magnify=reduced?1:1+.045*(i===this.selected?1:0)+proximity*(press*.15+this.bounce*.065);
            b.style.setProperty('--tab-magnify',magnify.toFixed(4));
            b.style.setProperty('--tab-lift',reduced?'0px':`${(-proximity*(press*2+this.bounce)).toFixed(3)}px`);
            b.classList.toggle('is-preview',this.pointer!==null&&i===this.preview);
        });
    }
    getState(){return {selected:this.selected,preview:this.preview,position:this.x,target:this.target,velocity:this.vx,slot:this.slot,dragging:this.pointer!==null,animating:!!this.frame}}
}
const bar=document.getElementById('mobile-nav');
if(bar)window.afterBellTabBar=new LiquidTabBar(bar);
})();
