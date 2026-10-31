// Execute the actual rendered inline script with a minimal DOM; no browser,
// token storage, database, connection or implicit confirmation.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
(async()=>{
  let checks=0;
  for (const language of ['sl','en']) {
    const html=fs.readFileSync(process.argv[2]+'/'+language+'.html','utf8');
    const script=html.match(/<script nonce="[^"]+">([\s\S]*?)<\/script>/)[1];
    const elements={};
    const id='00000000-0000-4000-a000-000000000001';
    const fragment=new URLSearchParams({token:'fhv1_'+'a'.repeat(64),accountId:id,serverId:id,email:'target@synthetic.invalid'});
    const location=new URL('https://synthetic.invalid/jivie/index.php?controller=EmailVerificationController&action=show&plugin=FamilyHub#'+fragment);
    let posts=0;
    vm.runInNewContext(script,{URL,URLSearchParams,location,history:{replaceState(){}},document:{getElementById(id){return elements[id]??=( {hidden:true,disabled:false,textContent:''});}},fetch:async()=>{posts++;throw Error('synthetic offline');}});
    assert.equal(elements.server.textContent,(language==='sl'?'Strežnik':'Server')+': https://synthetic.invalid/jivie');checks++;
    assert.equal(elements.account.textContent,(language==='sl'?'Račun':'Account')+': target@synthetic.invalid');checks++;
    assert.equal(posts,0);checks++;
    await elements.confirm.onclick();
    assert.equal(elements.status.textContent,language==='sl'?'Potrditev trenutno ni na voljo. Poskusi znova.':'Verification is temporarily unavailable. Please try again.');checks++;
    assert.equal(elements.confirm.disabled,false);checks++;
  }
  console.log(`PASS ${checks} rendered SL/EN landing labels, no implicit POST, offline retry`);
})().catch(e=>{console.error(e);process.exit(1);});
