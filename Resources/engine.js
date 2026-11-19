// Engine cờ tướng – dùng chung với bản web

var MATE=30000, MATE_B=29000, INF=32000;
var B=new Int8Array(90), side=0, kpos=[0,0], hlo=0, hhi=0;
// piece code: color*8 + type+1 ; types 0K 1A 2B 3N 4R 5C 6P
var VAL=[0,200,200,400,900,450,100];
var ZL=new Int32Array(16*90), ZH=new Int32Array(16*90), SL, SH;
(function(){var s=0x9e3779b9;function r(){s^=s<<13;s^=s>>>17;s^=s<<5;return s|0;}
 for(var i=0;i<16*90;i++){ZL[i]=r();ZH[i]=r();} SL=r(); SH=r();})();
var MAXSP=2048, capS=new Int8Array(MAXSP), hlS=new Int32Array(MAXSP), hhS=new Int32Array(MAXSP), sp=0;
var PST=[
 null,null,null,
 [4,8,16,12,4,12,16,8,4, 4,10,28,16,8,16,28,10,4, 12,14,16,20,18,20,16,14,12, 8,24,18,24,20,24,18,24,8, 6,16,14,18,16,18,14,16,6, 4,12,16,14,12,14,16,12,4, 2,6,8,6,10,6,8,6,2, 4,2,8,8,4,8,8,2,4, 0,2,4,4,-2,4,4,2,0, 0,-4,0,0,0,0,0,-4,0],
 [14,14,12,18,16,18,12,14,14, 16,20,18,24,26,24,18,20,16, 12,12,12,18,18,18,12,12,12, 12,18,16,22,22,22,16,18,12, 12,14,12,18,18,18,12,14,12, 12,16,14,20,20,20,14,16,12, 6,10,8,14,14,14,8,10,6, 4,8,6,14,12,14,6,8,4, 8,4,8,16,8,16,8,4,8, -2,10,6,14,12,14,6,10,-2],
 [6,4,0,-10,-12,-10,0,4,6, 2,2,0,-4,-14,-4,0,2,2, 2,2,0,-10,-8,-10,0,2,2, 0,0,-2,4,10,4,-2,0,0, 0,0,0,2,8,2,0,0,0, -2,0,4,2,6,2,4,0,-2, 0,0,0,2,4,2,0,0,0, 4,0,8,6,10,6,8,0,4, 0,2,4,6,6,6,4,2,0, 0,0,2,6,6,6,2,0,0],
 [60,63,66,69,72,69,66,63,60, 78,96,116,140,180,140,116,96,78, 74,86,102,120,140,120,102,86,74, 70,80,90,94,100,94,90,80,70, 66,72,78,78,80,78,78,72,66, 2,0,8,0,8,0,8,0,2, 0,0,-2,0,4,0,-2,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0]
];
var INIT="rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR";
var FCH={k:0,a:1,b:2,n:3,r:4,c:5,p:6};
function reset(st){
  B.fill(0); side=st||0; sp=0; hlo=0; hhi=0; if(side){hlo^=SL;hhi^=SH;}
  var rows=INIT.split('/');
  for(var r=0;r<10;r++){var c=0;for(var ch of rows[r]){
    if(ch>='1'&&ch<='9'){c+=+ch;continue;}
    var lo=ch.toLowerCase(), col=(ch===lo)?1:0, p=col*8+FCH[lo]+1, sq=r*9+c;
    B[sq]=p; hlo^=ZL[p*90+sq]; hhi^=ZH[p*90+sq]; if(FCH[lo]===0)kpos[col]=sq; c++;}}
}
function make(m){
  var f=m>>7,t=m&127,p=B[f],c=B[t];
  capS[sp]=c; hlS[sp]=hlo; hhS[sp]=hhi; sp++;
  hlo^=ZL[p*90+f]^ZL[p*90+t]; hhi^=ZH[p*90+f]^ZH[p*90+t];
  if(c){hlo^=ZL[c*90+t]; hhi^=ZH[c*90+t];}
  B[t]=p; B[f]=0; if((p&7)===1)kpos[p>>3]=t;
  side^=1; hlo^=SL; hhi^=SH;
}
function unmake(m){
  sp--; var f=m>>7,t=m&127,p=B[t];
  B[f]=p; B[t]=capS[sp]; if((p&7)===1)kpos[p>>3]=f;
  hlo=hlS[sp]; hhi=hhS[sp]; side^=1;
}
function inPal(s,r,c){return c>=3&&c<=5&&(s===0?(r>=7&&r<=9):(r>=0&&r<=2));}
var OR=[[-1,0],[1,0],[0,-1],[0,1]], DG=[[-1,-1],[-1,1],[1,-1],[1,1]];
var KN=[[-2,-1,-1,0],[-2,1,-1,0],[2,-1,1,0],[2,1,1,0],[-1,-2,0,-1],[1,-2,0,-1],[-1,2,0,1],[1,2,0,1]];
function gen(caps){
  var mv=[], s=side, i, d, nr, nc, to, q;
  for(var sq=0;sq<90;sq++){
    var p=B[sq]; if(!p||(p>>3)!==s)continue;
    var r=(sq/9)|0, c=sq%9, t=(p&7)-1;
    var add=function(to){var q=B[to]; if(q){if((q>>3)!==s)mv.push(sq<<7|to);} else if(!caps)mv.push(sq<<7|to);};
    switch(t){
    case 0: for(i=0;i<4;i++){nr=r+OR[i][0];nc=c+OR[i][1]; if(inPal(s,nr,nc))add(nr*9+nc);} break;
    case 1: for(i=0;i<4;i++){nr=r+DG[i][0];nc=c+DG[i][1]; if(inPal(s,nr,nc))add(nr*9+nc);} break;
    case 2: for(i=0;i<4;i++){nr=r+2*DG[i][0];nc=c+2*DG[i][1];
      if(nr<0||nr>9||nc<0||nc>8)continue; if(s===0?nr<5:nr>4)continue;
      if(B[(r+DG[i][0])*9+c+DG[i][1]])continue; add(nr*9+nc);} break;
    case 3: for(i=0;i<8;i++){d=KN[i];nr=r+d[0];nc=c+d[1]; if(nr<0||nr>9||nc<0||nc>8)continue;
      if(B[(r+d[2])*9+c+d[3]])continue; add(nr*9+nc);} break;
    case 4: for(i=0;i<4;i++){nr=r+OR[i][0];nc=c+OR[i][1];
      while(nr>=0&&nr<=9&&nc>=0&&nc<=8){to=nr*9+nc; if(B[to]){add(to);break;} if(!caps)mv.push(sq<<7|to); nr+=OR[i][0];nc+=OR[i][1];}} break;
    case 5: for(i=0;i<4;i++){nr=r+OR[i][0];nc=c+OR[i][1]; var scr=false;
      while(nr>=0&&nr<=9&&nc>=0&&nc<=8){to=nr*9+nc; q=B[to];
        if(!scr){ if(q)scr=true; else if(!caps)mv.push(sq<<7|to); }
        else if(q){ if((q>>3)!==s)mv.push(sq<<7|to); break; }
        nr+=OR[i][0];nc+=OR[i][1];}} break;
    case 6: var fw=s===0?-1:1; nr=r+fw; if(nr>=0&&nr<=9)add(nr*9+c);
      if(s===0?r<=4:r>=5){ if(c>0)add(r*9+c-1); if(c<8)add(r*9+c+1);} break;
    }
  }
  return mv;
}
function inCheck(col){
  var k=kpos[col], r=(k/9)|0, c=k%9, e=(1-col)*8, i, nr, nc, q, scr;
  for(i=0;i<4;i++){nr=r+OR[i][0];nc=c+OR[i][1];scr=false;
    while(nr>=0&&nr<=9&&nc>=0&&nc<=8){q=B[nr*9+nc];
      if(q){ if(!scr){ if(q===e+5||(q===e+1&&OR[i][1]===0))return true; scr=true;} else { if(q===e+6)return true; break; } }
      nr+=OR[i][0];nc+=OR[i][1];}}
  for(i=0;i<8;i++){var d=KN[i]; nr=r+d[0]; nc=c+d[1]; if(nr<0||nr>9||nc<0||nc>8)continue;
    if(B[nr*9+nc]!==e+4)continue;
    var dr=-d[0], dc=-d[1], lr, lc;
    if(Math.abs(dr)===2){lr=nr+(dr>0?1:-1);lc=nc;} else {lr=nr;lc=nc+(dc>0?1:-1);}
    if(!B[lr*9+lc])return true;}
  var pf=col===0?-1:1; nr=r+pf;
  if(nr>=0&&nr<=9&&B[nr*9+c]===e+7)return true;
  if(c>0&&B[r*9+c-1]===e+7)return true;
  if(c<8&&B[r*9+c+1]===e+7)return true;
  return false;
}
function legalMoves(){var out=[],mv=gen(false);for(var m of mv){make(m);if(!inCheck(side^1))out.push(m);unmake(m);}return out;}
function evaluate(){
  var s=0;
  for(var sq=0;sq<90;sq++){var p=B[sq]; if(!p)continue; var t=(p&7)-1, col=p>>3;
    var v=VAL[t]; var tb=PST[t]; if(tb)v+=tb[col===0?sq:89-sq];
    s+=col===0?v:-v;}
  return side===0?s:-s;
}
// ---- search ----
var TTN=1<<20, TTM=TTN-1, ttK=new Int32Array(TTN), ttMv=new Int16Array(TTN), ttD=new Int8Array(TTN), ttF=new Int8Array(TTN), ttS=new Int16Array(TTN);
var hist=new Int32Array(90*128), killers=[], nodes=0, stopT=0, stopped=false;
function isRep(){for(var i=sp-2;i>=0&&i>=sp-100;i-=2){if(hlS[i]===hlo&&hhS[i]===hhi)return true;}return false;}
function qs(a,b,ply){
  nodes++; if((nodes&4095)===0&&Date.now()>stopT)stopped=true; if(stopped)return 0;
  var st=evaluate(); if(ply>60)return st; if(st>=b)return st; if(st>a)a=st;
  var mv=gen(true), sc=mv.map(function(m){return VAL[(B[m&127]&7)-1]*10-((B[m>>7]&7));});
  for(var i=0;i<mv.length;i++){var bi=i;for(var j=i+1;j<mv.length;j++)if(sc[j]>sc[bi])bi=j;
    var t=mv[i];mv[i]=mv[bi];mv[bi]=t; t=sc[i];sc[i]=sc[bi];sc[bi]=t;
    var m=mv[i]; if((B[m&127]&7)===1)return MATE-ply;
    make(m); if(inCheck(side^1)){unmake(m);continue;}
    var s=-qs(-b,-a,ply+1); unmake(m);
    if(s>=b)return s; if(s>a)a=s;}
  return a;
}
function ab(depth,a,b,ply){
  if(ply>0&&isRep())return 0;
  var chk=inCheck(side); if(chk)depth++;
  if(depth<=0)return qs(a,b,ply);
  nodes++; if((nodes&4095)===0&&Date.now()>stopT)stopped=true; if(stopped)return 0;
  var idx=hlo&TTM, ttMove=0;
  if(ttK[idx]===hhi){ ttMove=ttMv[idx]; if(ply>0&&ttD[idx]>=depth){var s0=ttS[idx]; if(s0>MATE_B)s0-=ply; else if(s0<-MATE_B)s0+=ply;
    var f=ttF[idx]; if(f===0)return s0; if(f===1&&s0>=b)return s0; if(f===2&&s0<=a)return s0;}}
  var mv=gen(false), n=mv.length, sc=new Array(n), k=killers[ply]||(killers[ply]=[0,0]);
  for(var i=0;i<n;i++){var m=mv[i], cap=B[m&127];
    sc[i]= m===ttMove?1e7 : cap?1e6+VAL[(cap&7)-1]*10-(B[m>>7]&7) : m===k[0]?9e5 : m===k[1]?8e5 : hist[m];}
  var best=-INF, bestM=0, legal=0, a0=a;
  for(i=0;i<n;i++){
    var bi=i;for(var j=i+1;j<n;j++)if(sc[j]>sc[bi])bi=j;
    var t=mv[i];mv[i]=mv[bi];mv[bi]=t; t=sc[i];sc[i]=sc[bi];sc[bi]=t;
    m=mv[i]; var isCap=B[m&127]!==0;
    make(m); if(inCheck(side^1)){unmake(m);continue;}
    legal++; var s;
    if(legal===1) s=-ab(depth-1,-b,-a,ply+1);
    else{
      var red=(!isCap&&!chk&&depth>=3&&legal>4)?1:0;
      s=-ab(depth-1-red,-a-1,-a,ply+1);
      if(s>a&&red) s=-ab(depth-1,-a-1,-a,ply+1);
      if(s>a&&s<b) s=-ab(depth-1,-b,-a,ply+1);
    }
    unmake(m); if(stopped)return 0;
    if(s>best){best=s;bestM=m; if(s>a)a=s;}
    if(a>=b){ if(!isCap){ if(k[0]!==m){k[1]=k[0];k[0]=m;} hist[m]+=depth*depth; } break; }
  }
  if(!legal)return -MATE+ply;
  var ss=best; if(ss>MATE_B)ss+=ply; else if(ss<-MATE_B)ss-=ply;
  ttK[idx]=hhi; ttMv[idx]=bestM; ttD[idx]=depth; ttS[idx]=ss; ttF[idx]= best<=a0?2: best>=b?1:0;
  return best;
}
function getPV(first){
  var pv=[], done=[], m=first;
  for(var i=0;i<12&&m;i++){
    var lm=legalMoves(); if(lm.indexOf(m)<0)break;
    pv.push(m); make(m); done.push(m);
    var idx=hlo&TTM; m= ttK[idx]===hhi? ttMv[idx]:0;
  }
  while(done.length)unmake(done.pop());
  return pv;
}
function think(timeMs,maxDepth,onInfo){
  nodes=0; stopped=false; stopT=Date.now()+timeMs; killers=[]; hist.fill(0);
  var root=legalMoves(); if(!root.length)return {move:0,score:-MATE,pv:[],depth:0};
  var bestM=root[0], bestS=0, pv=[bestM], dd=0;
  for(var d=1;d<=maxDepth;d++){
    var s=ab(d,-INF,INF,0);
    if(stopped&&d>1)break;
    var idx=hlo&TTM; if(ttK[idx]===hhi&&ttMv[idx]&&root.indexOf(ttMv[idx])>=0){bestM=ttMv[idx];}
    bestS=s; dd=d; pv=getPV(bestM);
    if(onInfo)onInfo({depth:d,score:s,pv:pv,nodes:nodes});
    if(Math.abs(s)>MATE_B)break;
    if(Date.now()>stopT)break;
  }
  return {move:bestM,score:bestS,pv:pv,depth:dd};
}
function setPos(moves,st){reset(st);for(var m of moves)make(m);}
function easyPick(noise){
  var root=legalMoves(), best=null, bs=-INF;
  for(var m of root){make(m); stopT=Date.now()+1e4; stopped=false; var s=-ab(1,-INF,INF,1)+ (Math.random()*2-1)*noise; unmake(m); if(s>bs){bs=s;best=m;}}
  return best;
}

// ===== iOS API (gọi từ Swift qua JavaScriptCore) =====
var VN=["Tg","S","T","M","X","P","B"];
function notate(m){
  var f=m>>7,t=m&127,p=B[f],col=p>>3,ty=(p&7)-1;
  var fr=(f/9)|0,fc=f%9,tr=(t/9)|0,tc=t%9;
  var file=function(c){return col===0?9-c:c+1;};
  var pre=VN[ty]+file(fc);
  if(ty>=3){var same=[];for(var r=0;r<10;r++)if(B[r*9+fc]===p)same.push(r);
    if(same.length===2){ same.sort(function(a,b){return col===0?a-b:b-a;}); pre=VN[ty]+(same.indexOf(fr)===0?'t':'s'); }
    else if(same.length>2){ same.sort(function(a,b){return col===0?a-b:b-a;}); pre=VN[ty]+(same.indexOf(fr)+1); }}
  if(fr===tr)return pre+'-'+file(tc);
  var fw=col===0?fr-tr:tr-fr;
  var num=(ty===1||ty===2||ty===3)?file(tc):Math.abs(fr-tr);
  return pre+(fw>0?'.':'/')+num;
}
var PCH="kabnrcp";
function setBoard(s,st){
  B.fill(0); sp=0; hlo=0; hhi=0; side=st?1:0; if(side){hlo^=SL;hhi^=SH;}
  for(var i=0;i<90;i++){var ch=s.charAt(i); if(ch==="."||ch==="")continue;
    var lo=ch.toLowerCase(), col=(ch===lo)?1:0, t=PCH.indexOf(lo); if(t<0)continue;
    var p=col*8+t+1; B[i]=p; hlo^=ZL[p*90+i]; hhi^=ZH[p*90+i]; if(t===0)kpos[col]=i;}
}
function boardStr(){var s="";for(var i=0;i<90;i++){var p=B[i]; if(!p){s+=".";continue;} var ch=PCH.charAt((p&7)-1); s+=(p>>3)?ch:ch.toUpperCase();}return s;}
function apiFindMove(prev,next,st){
  var sides=[st?1:0, st?0:1];
  for(var k=0;k<2;k++){ setBoard(prev,sides[k]);
    var lm=legalMoves();
    for(var a=0;a<lm.length;a++){var m=lm[a], n1=notate(m); make(m);
      if(boardStr()===next){var r={side:side,from:m>>7,to:m&127,notes:[n1]}; unmake(m); return JSON.stringify(r);} unmake(m);} }
  for(k=0;k<2;k++){ setBoard(prev,sides[k]); var l1=legalMoves();
    for(a=0;a<l1.length;a++){var m1=l1[a], na=notate(m1); make(m1); var l2=legalMoves();
      for(var b=0;b<l2.length;b++){var m2=l2[b], nb=notate(m2); make(m2);
        if(boardStr()===next){var r2={side:side,from:m2>>7,to:m2&127,notes:[na,nb]}; unmake(m2); unmake(m1); return JSON.stringify(r2);} unmake(m2);}
      unmake(m1);} }
  return "null";
}
function apiAnalyze(s,st,ms){
  setBoard(s,st); var chk=inCheck(side);
  if(!legalMoves().length) return JSON.stringify({over:true,side:side,check:chk});
  var r=think(ms,40,null), pv=[], done=[];
  for(var i=0;i<r.pv.length;i++){pv.push(notate(r.pv[i])); make(r.pv[i]); done.push(r.pv[i]);}
  while(done.length)unmake(done.pop());
  var mate=Math.abs(r.score)>MATE_B?Math.ceil((MATE-Math.abs(r.score))/2)*(r.score>0?1:-1):0;
  return JSON.stringify({over:false,side:side,check:chk,from:r.move>>7,to:r.move&127,score:r.score,mate:mate,depth:r.depth,pv:pv});
}
