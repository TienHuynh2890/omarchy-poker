.pragma library

// Texas Hold'em heads-up (Player vs AI), simplified betting.

var RANKS = [2,3,4,5,6,7,8,9,10,11,12,13,14];
var SUITS = ["s","h","d","c"];
var RANK_STR = {2:"2",3:"3",4:"4",5:"5",6:"6",7:"7",8:"8",9:"9",10:"10",11:"J",12:"Q",13:"K",14:"A"};
var SUIT_SYM = {s:"♠", h:"♥", d:"♦", c:"♣"};

function card(r,s){ return {r:r,s:s}; }
function cardStr(c){ return RANK_STR[c.r] + SUIT_SYM[c.s]; }

function newDeck(){
  var d=[];
  for(var i=0;i<RANKS.length;i++) for(var j=0;j<SUITS.length;j++) d.push(card(RANKS[i],SUITS[j]));
  return d;
}
function shuffle(a){
  for(var i=a.length-1;i>0;i--){ var j=Math.floor(Math.random()*(i+1)); var t=a[i]; a[i]=a[j]; a[j]=t; }
  return a;
}
function clone(s){ return JSON.parse(JSON.stringify(s)); }

// -------- Hand evaluation (best 5 of 7) --------
function combos(arr,k){
  var res=[];
  function go(start,cur){
    if(cur.length===k){ res.push(cur.slice()); return; }
    for(var i=start;i<arr.length;i++){ cur.push(arr[i]); go(i+1,cur); cur.pop(); }
  }
  go(0,[]); return res;
}
function isStraight(ranksDesc){
  var r=ranksDesc.slice();
  if(r[0]===14 && r[1]===5 && r[2]===4 && r[3]===3 && r[4]===2) return 5;
  for(var i=0;i<4;i++) if(r[i]-1!==r[i+1]) return 0;
  return r[0];
}
function eval5(cards){
  var ranks=[]; var suits={s:0,h:0,d:0,c:0}; var counts={};
  for(var i=0;i<5;i++){ ranks.push(cards[i].r); suits[cards[i].s]++; counts[cards[i].r]=(counts[cards[i].r]||0)+1; }
  ranks.sort(function(a,b){return b-a;});
  var flushSuit=null; for(var su in suits) if(suits[su]===5) flushSuit=su;
  var uniq=Object.keys(counts).map(function(x){return parseInt(x,10);}).sort(function(a,b){return b-a;});
  var groups=[];
  for(var k in counts) groups.push({r:parseInt(k,10),c:counts[k]});
  groups.sort(function(a,b){ if(b.c!==a.c) return b.c-a.c; return b.r-a.r; });
  var straightHigh = isStraight(uniq.length===5?uniq:ranks);
  if(flushSuit){
    var fr=[]; for(var i=0;i<5;i++) if(cards[i].s===flushSuit) fr.push(cards[i].r);
    fr.sort(function(a,b){return b-a;});
    var sf=isStraight(fr);
    if(sf) return {cat:8, t:[sf], name: sf===14?"Thùng phá sảnh (Royal)":"Thùng phá sảnh"};
  }
  if(groups[0].c===4){ var kicker=groups[1].r; return {cat:7,t:[groups[0].r,kicker],name:"Tứ quý"}; }
  if(groups[0].c===3 && groups[1].c===2){ return {cat:6,t:[groups[0].r,groups[1].r],name:"Cù lũ"}; }
  if(flushSuit){ return {cat:5,t:ranks,name:"Thùng"}; }
  if(straightHigh){ return {cat:4,t:[straightHigh],name:"Sảnh"}; }
  if(groups[0].c===3){ var ks=[]; for(var i=1;i<groups.length;i++) ks.push(groups[i].r); ks.sort(function(a,b){return b-a;}); return {cat:3,t:[groups[0].r].concat(ks),name:"Sám cô"}; }
  if(groups[0].c===2 && groups[1].c===2){ var hi=Math.max(groups[0].r,groups[1].r), lo=Math.min(groups[0].r,groups[1].r), k2=groups[2].r; return {cat:2,t:[hi,lo,k2],name:"Hai đôi"}; }
  if(groups[0].c===2){ var ks2=[]; for(var i=1;i<groups.length;i++) ks2.push(groups[i].r); ks2.sort(function(a,b){return b-a;}); return {cat:1,t:[groups[0].r].concat(ks2),name:"Một đôi"}; }
  return {cat:0,t:ranks,name:"Mậu thầu"};
}
function cmpScore(a,b){
  if(a.cat!==b.cat) return a.cat-b.cat;
  for(var i=0;i<Math.max(a.t.length,b.t.length);i++){ var av=a.t[i]||0, bv=b.t[i]||0; if(av!==bv) return av-bv; }
  return 0;
}
function bestHand(cards){
  var cs = combos(cards,5); var best=null;
  for(var i=0;i<cs.length;i++){ var s=eval5(cs[i]); if(!best || cmpScore(s,best)>0) best=s; }
  return best || {cat:0,t:[],name:""};
}

// -------- Game --------
var SB=10, BB=20, START=1000;

function newGame(){
  return {
    deck: [], community: [], pot: 0,
    players: [
      {id:"p", name:"Bạn", chips:START, hole:[], bet:0, folded:false, allin:false, acted:false, dead:false, rouletteShots:0},
      {id:"ai", name:"AI", chips:START, hole:[], bet:0, folded:false, allin:false, acted:false, dead:false, rouletteShots:0}
    ],
    dealer: 0,
    turn: 0, stage: "intro",
    toCall: 0, minRaise: BB,
    message: "Chào mừng! Bấm Bắt đầu chơi", winner: "", handName:"", lastFx: null, fxId: 0,
    roulette: null, gameOver: false, peakChips: START,
    ai: { level: 0 }
  };
}

function resetBets(s){
  for(var i=0;i<2;i++){ s.players[i].bet=0; s.players[i].acted=false; }
  s.toCall=0; s.minRaise=BB;
}

function post(s, idx, amt){
  var p=s.players[idx]; var a=Math.min(amt,p.chips);
  p.chips -= a; p.bet += a; s.pot += a;
  if(p.chips===0) p.allin=true;
  return a;
}

function dealHole(s){
  s.players[0].hole=[s.deck.pop(), s.deck.pop()];
  s.players[1].hole=[s.deck.pop(), s.deck.pop()];
}
function dealCommunity(s,n){ for(var i=0;i<n;i++) s.community.push(s.deck.pop()); }

function canAct(p){ return p && !p.folded && !p.allin; }

function nextActor(s, from){
  var o = 1-from;
  if(canAct(s.players[o])) return o;
  if(canAct(s.players[from])) return from;
  return -1;
}

function onlyOneLeft(s){
  var alive=0; for(var i=0;i<2;i++) if(!s.players[i].folded) alive++; return alive===1;
}

function roundComplete(s){
  // betting round complete when every player who can act has acted and bets are matched
  for(var i=0;i<2;i++){
    var p=s.players[i];
    if(p.folded || p.allin) continue;
    if(!p.acted) return false;
    if(p.bet !== s.toCall) return false;
  }
  return true;
}

function activeCount(s){
  var n=0; for(var i=0;i<2;i++) if(canAct(s.players[i])) n++; return n;
}

function awardPot(s, idx, msg){
  s.players[idx].chips += s.pot;
  s.winner = s.players[idx].name;
  s.message = msg;
  s.pot = 0;
  s.stage = "showdown";
}

function checkBustRoulette(s){
  // if someone is bust after hand resolution, trigger Liar's Bar style roulette
  // mỗi lần bắn tăng tỉ lệ: 1/6, 2/6, ... 6/6
  for(var i=0;i<2;i++){
    if(s.players[i].chips <= 0 && !s.players[i].dead){
      var shots = s.players[i].rouletteShots || 0;
      var bulletCount = Math.min(6, shots + 1);
      var chamber = Math.floor(Math.random()*6)+1;
      // nạp bulletCount viên vào các buồng 1..bulletCount (ngẫu nhiên tương đương)
      var isDead = chamber <= bulletCount;
      var handMsg = s.message || "";
      s.stage = "roulette";
      s.roulette = { who: i, done: false, dead: false, chamber: chamber, bulletCount: bulletCount, phase: "ready", handMsg: handMsg, _isDead: isDead };
      s.message = handMsg ? (handMsg + " • " + s.players[i].name + " hết tiền! Roulette " + bulletCount + "/6...") : (s.players[i].name + " hết tiền! Roulette " + bulletCount + "/6...");
      return true;
    }
  }
  return false;
}

function showdown(s){
  s.stage = "showdown";
  if(onlyOneLeft(s)){
    var w = s.players[0].folded ? 1 : 0;
    awardPot(s, w, s.players[w].name + " thắng (đối thủ bỏ bài)");
    checkBustRoulette(s);
    return s;
  }
  var h0 = bestHand(s.players[0].hole.concat(s.community));
  var h1 = bestHand(s.players[1].hole.concat(s.community));
  s.players[0].handName = h0.name; s.players[1].handName = h1.name;
  var c = cmpScore(h0,h1);
  if(c > 0){ awardPot(s,0,"Bạn thắng: "+h0.name); s.handName=h0.name; }
  else if(c < 0){ awardPot(s,1,"AI thắng: "+h1.name); s.handName=h1.name; }
  else {
    var half = Math.floor(s.pot/2);
    s.players[0].chips += half; s.players[1].chips += (s.pot - half);
    s.message = "Hòa: " + h0.name; s.winner = "Hòa"; s.handName = h0.name; s.pot = 0;
  }
  s.stage = "showdown";
  checkBustRoulette(s);
  return s;
}

function fireRoulette(state){
  var s = clone(state);
  if(s.stage !== "roulette" || !s.roulette || s.roulette.done) return s;
  var r = s.roulette;
  r.done = true;
  r.phase = "result";
  var bulletCount = r.bulletCount || 1;
  var isDead = (typeof r._isDead === "boolean") ? r._isDead : (r.chamber <= bulletCount);
  r.dead = isDead;
  if(isDead){
    s.players[r.who].dead = true;
    s.players[r.who].chips = 0;
    var other = 1 - r.who;
    s.winner = s.players[other].name;
    s.handName = "Đạn thật!";
    s.message = s.players[r.who].name + " dính đạn (buồng " + r.chamber + ", " + bulletCount + "/6)! " + s.players[other].name + " thắng chung cuộc!";
    fx(s, "shot", r.who, 0);
    if(r.who === 1){
      // AI chết: chờ rồi mới hiện thắng
      s.stage = "dead_wait";
      s.gameOver = false;
    } else {
      // người chơi chết: thua luôn
      s.gameOver = true;
      s.stage = "gameover";
    }
  } else {
    // sống sót: lần sau tăng đạn
    s.players[r.who].rouletteShots = (s.players[r.who].rouletteShots || 0) + 1;
    s.players[r.who].chips = 500;
    s.stage = "showdown"; // allow next hand
    s.winner = "Sống sót";
    s.handName = "Sống sót";
    s.message = s.players[r.who].name + " sống sót! (buồng " + r.chamber + ", " + bulletCount + "/6) +500 chip. Lần sau " + Math.min(6, bulletCount + 1) + "/6.";
    fx(s, "survive", r.who, 500);
  }
  s.roulette = r;
  return s;
}

function advanceStage(s){
  // move bets already in pot; reset for new round
  for(var i=0;i<2;i++){ s.players[i].bet = 0; s.players[i].acted = false; }
  s.toCall = 0; s.minRaise = BB;

  if(onlyOneLeft(s)) return showdown(s);

  // if no one (or only one side effectively) can act, run out board
  if(activeCount(s) < 2){
    while(s.community.length < 5) dealCommunity(s, s.community.length===0 ? 3 : 1);
    return showdown(s);
  }

  if(s.stage === "preflop"){ dealCommunity(s,3); s.stage="flop"; s.message="Flop"; }
  else if(s.stage === "flop"){ dealCommunity(s,1); s.stage="turn"; s.message="Turn"; }
  else if(s.stage === "turn"){ dealCommunity(s,1); s.stage="river"; s.message="River"; }
  else if(s.stage === "river"){ return showdown(s); }

  // postflop first to act in heads-up: non-dealer (BB)
  s.turn = 1 - s.dealer;
  if(!canAct(s.players[s.turn])) s.turn = nextActor(s, s.turn);
  if(s.turn === -1) return advanceStage(s);
  return s;
}

function startHand(state){
  var s = clone(state);
  // full reset if game over or replay
  if(s.gameOver || s.stage === "intro"){
    var fresh = newGame();
    fresh.dealer = s.dealer; // keep alternation feel
    // keep AI level across hands
    if (s.ai) fresh.ai.level = s.ai.level || 0;
    // keep peakChips accumulated? reset on fresh game
    s = fresh;
  }
  // if waiting after AI death or roulette pending, don't start
  if(s.stage === "dead_wait") return s;
  if(s.stage === "roulette" && s.roulette && !s.roulette.done) return s;
  // clear roulette result marker but keep if gameover handled above
  s.roulette = null;
  // only refill if someone somehow has 0 but not in roulette flow (safety)
  for(var i=0;i<2;i++){ if(s.players[i].chips <= 0 && !s.players[i].dead) s.players[i].chips = START; }
  s.deck = shuffle(newDeck()); s.community = []; s.pot = 0; s.winner = ""; s.handName = ""; s.lastFx = null;
  for(var i=0;i<2;i++){
    s.players[i].hole = []; s.players[i].bet = 0; s.players[i].folded = false; s.players[i].allin = false; s.players[i].acted = false;
  }
  s.dealer = 1 - s.dealer; // alternate
  s.stage = "preflop";

  var sb = s.dealer, bb = 1 - s.dealer;
  // ensure blinds possible
  if(s.players[sb].chips <= 0 || s.players[bb].chips <= 0) {
    // fallback safety
    for(var j=0;j<2;j++){ if(s.players[j].chips <= 0) s.players[j].chips = START; }
  }
  post(s, sb, SB);
  post(s, bb, BB);
  s.toCall = BB; s.minRaise = BB;
  s.players[sb].acted = false;
  s.players[bb].acted = false;

  var sbName = s.players[sb].name || (sb===0?"Bạn":"AI");
  var bbName = s.players[bb].name || (bb===0?"Bạn":"AI");
  s.message = "Preflop • SB " + sbName + " " + SB + ", BB " + bbName + " " + BB;

  dealHole(s);
  s.turn = sb; // SB/dealer acts first preflop in heads-up
  if(!canAct(s.players[s.turn])) s.turn = nextActor(s, s.turn);
  return s;
}

function claimVictory(state){
  var s = clone(state);
  if(s.stage !== "dead_wait") return s;
  s.stage = "gameover";
  s.gameOver = true;
  return s;
}

function fx(s, type, who, amount){
  s.fxId = (s.fxId || 0) + 1;
  s.lastFx = { type: type, who: who, amount: amount || 0, id: s.fxId };
}

function doAction(state, action, amount){
  var s = clone(state);
  if(s.stage === "idle" || s.stage === "intro" || s.stage === "showdown" || s.stage === "roulette" || s.stage === "gameover" || s.stage === "dead_wait") return s;
  var p = s.players[s.turn];
  if(!p || p.folded || p.allin) return s;
  var other = 1 - s.turn;

  if(action === "fold"){
    p.folded = true; p.acted = true;
    s.message = p.name + " bỏ bài";
    fx(s, "fold", s.turn, 0);
    return showdown(s);
  }

  if(action === "check" || action === "call"){
    var need = s.toCall - p.bet;
    if(need <= 0){
      p.acted = true;
      s.message = p.name + " check";
      fx(s, "check", s.turn, 0);
    } else {
      var a = post(s, s.turn, need);
      p.acted = true;
      s.message = p.name + " call " + a;
      fx(s, "call", s.turn, a);
    }
  } else if(action === "allin"){
    var addAll = p.chips;
    if(addAll <= 0){ p.acted = true; s.message = p.name + " all-in"; }
    else {
      var prevToCall = s.toCall;
      post(s, s.turn, addAll);
      p.acted = true;
      p.allin = true;
      if(p.bet > prevToCall){
        var raiseByAll = p.bet - prevToCall;
        if(raiseByAll >= s.minRaise) s.minRaise = raiseByAll;
        s.toCall = p.bet;
        if(canAct(s.players[other])) s.players[other].acted = false;
      }
      s.message = p.name + " ALL-IN " + p.bet;
      fx(s, "allin", s.turn, addAll);
    }
  } else if(action === "raise"){
    var need2 = Math.max(0, s.toCall - p.bet);
    var target = Math.max(s.toCall + s.minRaise, (amount || 0));
    // target is desired total bet level; ensure at least a valid raise if possible
    var maxTotal = p.bet + p.chips;
    if(target > maxTotal) target = maxTotal;
    if(target <= s.toCall){
      // can't raise, treat as call/check
      var need3 = s.toCall - p.bet;
      if(need3 <= 0){ p.acted = true; s.message = p.name + " check"; fx(s, "check", s.turn, 0); }
      else { var a3 = post(s, s.turn, need3); p.acted = true; s.message = p.name + " call " + a3; fx(s, "call", s.turn, a3); }
    } else {
      var add = target - p.bet;
      post(s, s.turn, add);
      var raiseBy = p.bet - s.toCall;
      if(raiseBy >= s.minRaise) s.minRaise = raiseBy;
      s.toCall = p.bet;
      p.acted = true;
      // opponent must respond to raise
      if(canAct(s.players[other])) s.players[other].acted = false;
      s.message = p.name + " raise lên " + p.bet;
      fx(s, "raise", s.turn, add);
    }
  } else {
    return s;
  }

  if(onlyOneLeft(s)) return showdown(s);

  // if raise happened (toCall increased above others and opponent not acted), opponent acts
  // but simpler: check round completion
  if(roundComplete(s)){
    return advanceStage(s);
  } else {
    s.turn = nextActor(s, s.turn);
    if(s.turn === -1) return advanceStage(s);
    // if next actor somehow already satisfies completion (e.g. allin), advance
    if(roundComplete(s)) return advanceStage(s);
    return s;
  }
}

// -------- AI --------
function strengthScore(s, idx){
  var cards = s.players[idx].hole.concat(s.community);
  if(cards.length >= 5) return bestHand(cards);
  var h = s.players[idx].hole; if(h.length < 2) return {cat:0,t:[0]};
  var hi = Math.max(h[0].r,h[1].r), lo = Math.min(h[0].r,h[1].r);
  var pair = h[0].r === h[1].r, suited = h[0].s === h[1].s;
  var val = hi*2 + lo + (pair?50:0) + (suited?4:0) + ((hi-lo<=2)?3:0) + (hi>=13?4:0);
  return {cat: pair?1:0, t:[val]};
}

function aiChoose(state){
  var ai = state.players[1]; var need = state.toCall - ai.bet;
  var sc = strengthScore(state,1);
  var cfg = (state.ai && typeof state.ai === "object") ? state.ai : {};
  var lvl = cfg.level || 0; // 0 = normal, 1 = easy, 2 = hard
  var r = Math.random();
  var pot = state.pot || 0;
  var raiseTo = state.toCall + Math.max(BB*2, Math.floor(pot/2) || BB*2);

  var strong = (sc.cat>=2) || (sc.cat===1 && (sc.t[0]||0)>=11) || (state.community.length===0 && (sc.t[0]||0)>42);
  var medium = (sc.cat>=1) || (sc.t[0]||0)>30;

  if(need <= 0){
    var chkRaiseP = (lvl === 2) ? 0.75 : ((lvl === 1) ? 0.30 : 0.55);
    var raiseP = (lvl === 2) ? 0.45 : ((lvl === 1) ? 0.10 : 0.20);
    if(strong && r < chkRaiseP) return {a:"raise", amt: raiseTo};
    if(medium && r < raiseP) return {a:"raise", amt: state.toCall + BB*2};
    return {a:"check"};
  } else {
    var allinP = (lvl === 2) ? 0.30 : 0.18;
    var strongRaiseP = (lvl === 2) ? 0.60 : 0.40;
    var medCallP = (lvl === 2) ? 0.85 : ((lvl === 1) ? 0.90 : 0.75);
    if(strong && r < allinP) return {a:"allin"};
    if(strong && r < strongRaiseP && ai.chips > need + BB) return {a:"raise", amt: raiseTo};
    if(ai.chips <= need) return {a:"allin"};
    if(strong) return {a:"call"};
    if(medium && r < medCallP) return {a:"call"};
    if(need <= BB) return {a:"call"};
    if(r < (lvl === 2 ? 0.20 : 0.12) && need < ai.chips/3) return {a:"call"};
    if(lvl === 1 && r < 0.60 && need < ai.chips) return {a:"call"};
    return {a:"fold"};
  }
}

function stepAi(state){
  if(state.stage==="idle" || state.stage==="showdown") return state;
  if(state.turn!==1) return state;
  var choice = aiChoose(state);
  return doAction(state, choice.a, choice.amt);
}

function needAi(state){
  return state.stage!=="idle" && state.stage!=="showdown" && state.turn===1 && !state.players[1].folded && !state.players[1].allin;
}



function currentHandName(cards){
  if(!cards || cards.length < 2) return "";
  if(cards.length >= 5){
    var b = bestHand(cards);
    return b && b.name ? b.name : "";
  }
  // 2-4 cards: simple description
  var counts={}; var ranks=[];
  for(var i=0;i<cards.length;i++){ var r=cards[i].r; counts[r]=(counts[r]||0)+1; ranks.push(r); }
  ranks.sort(function(a,b){return b-a;});
  var pairs=[];
  for(var k in counts){ if(counts[k]===2) pairs.push(parseInt(k,10)); if(counts[k]===3) return "Sám cô " + RANK_STR[parseInt(k,10)]; if(counts[k]===4) return "Tứ quý " + RANK_STR[parseInt(k,10)]; }
  pairs.sort(function(a,b){return b-a;});
  if(pairs.length>=2) return "Hai đôi " + RANK_STR[pairs[0]] + " & " + RANK_STR[pairs[1]];
  if(pairs.length===1) return "Một đôi " + RANK_STR[pairs[0]];
  return "Bài cao " + RANK_STR[ranks[0]];
}

