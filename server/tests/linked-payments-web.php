<?php
// Included by the synthetic linked-payments HTTP suite. No real accounts.
$webName = $prefix.'_web_payment_delete';
$webUserId = $container['userModel']->create(['username'=>$webName, 'password'=>$password, 'role'=>'app-user']);
$webSession = data(call('auth.login', ['username'=>$webName, 'password'=>$password, 'deviceName'=>'Synthetic web payer']));
$webToken = $webSession['token'];
$webOrg = uuid();
data(call('scopes.create', ['id'=>$webOrg, 'kind'=>'organization', 'name'=>'Web retained source', 'accessPolicyVersion'=>2, 'requestId'=>uuid()], $webToken));
invite($webOrg, $names['external'], $webToken, $e);
$webLedger = uuid();
data(call('finance2.push', ['scopeId'=>$webOrg, 'operation'=>operation($webLedger, 'financeAccount', $richAccount)], $webToken));
$webExpense = uuid();
data(call('finance2.push', ['scopeId'=>$webOrg, 'operation'=>operation($webExpense, 'financeEntry', array_replace($payload, ['accountId'=>$webLedger, 'ledgerAccountId'=>$webLedger]))], $webToken));
$webPrivate = data(call('personal.ensure', [], $webToken))['scope']['id'];
$webCard = uuid();
data(call('finance2.push', ['scopeId'=>$webPrivate, 'operation'=>operation($webCard, 'personalFinanceAccount', $privateAccount)], $webToken));
$webEvent = data(call('finance3.paymentCommit', ['scopeId'=>$webOrg, 'entryId'=>$webExpense, 'expectedEntryRevision'=>1, 'eventId'=>uuid(), 'paidAt'=>$stamp, 'expectReimbursement'=>true, 'personalTarget'=>['scopeId'=>$webPrivate, 'accountId'=>$webCard], 'requestId'=>uuid()], $webToken))['event'];
data(call('finance3.paymentReimburse', ['scopeId'=>$webOrg, 'eventId'=>$webEvent['eventId'], 'expectedRevision'=>1, 'legId'=>uuid(), 'amountMinor'=>1000, 'paidAt'=>$stamp, 'organizationAccountId'=>$webLedger, 'requestId'=>uuid()], $webToken));
$webCookies = tempnam(sys_get_temp_dir(), 'familyhub-synthetic-web-');
function webDeletion($action, $params = null)
{
    global $webCookies;
    $curl = curl_init('http://127.0.0.1/index.php?controller=AccountDeletionController&action='.$action.'&plugin=FamilyHub');
    curl_setopt_array($curl, [CURLOPT_RETURNTRANSFER=>true, CURLOPT_COOKIEJAR=>$webCookies, CURLOPT_COOKIEFILE=>$webCookies]);
    if ($params !== null) {
        curl_setopt_array($curl, [CURLOPT_POST=>true, CURLOPT_POSTFIELDS=>http_build_query($params), CURLOPT_HTTPHEADER=>['Content-Type: application/x-www-form-urlencoded']]);
    }
    $body = curl_exec($curl);
    $status = curl_getinfo($curl, CURLINFO_HTTP_CODE);
    curl_close($curl);
    return ['status'=>$status, 'html'=>$body];
}
function webHidden($html, $name)
{
    if (!preg_match('/name="'.preg_quote($name, '/').'"\s+value="([^"]*)"/', $html, $match)) {
        throw new RuntimeException('Missing synthetic deletion form field');
    }
    return html_entity_decode($match[1], ENT_QUOTES, 'UTF-8');
}
try {
    $webIndex = webDeletion('index');
    check($webIndex['status'] === 200, 'standalone deletion website is available without a bearer');
    check(webDeletion('confirm')['status'] === 403, 'web confirmation remains POST-only');
    check(webDeletion('preview', ['username'=>$webName, 'password'=>$password])['status'] === 403, 'web preview requires current CSRF form');
    $webPreview = webDeletion('preview', ['csrf_token'=>webHidden($webIndex['html'], 'csrf_token'), 'username'=>$webName, 'password'=>$password, 'otp'=>'']);
    check($webPreview['status'] === 200 && webHidden($webPreview['html'], 'policyVersion') === '3', 'web review persists exact policy3 for linked financial facts');
    check(str_contains($webPreview['html'], 'data-linked-payment-scope="'.$webOrg.'"') && str_contains($webPreview['html'], 'approved reimbursements'), 'web review renders conditional payment and refund counts');
    check(str_contains($webPreview['html'], 'Private payment projections to remove: 1') && !str_contains($webPreview['html'], $webCard), 'web review explains private link removal without revealing card identity');
    $webParams = [];
    foreach (['csrf_token', 'token', 'operationId', 'receiptToken', 'previewHash', 'policyVersion'] as $key) {
        $webParams[$key] = webHidden($webPreview['html'], $key);
    }
    preg_match_all('/name="structures\[\]"\s+value="([^"]*)"/', $webPreview['html'], $structures);
    $webParams += ['owners'=>[$webOrg=>$sessions['external']['user']['accountId']], 'structures'=>array_map(fn($value)=>html_entity_decode($value, ENT_QUOTES, 'UTF-8'), $structures[1]), 'confirmation'=>'DELETE', 'password'=>'wrong synthetic password', 'otp'=>''];
    check(webDeletion('confirm', $webParams)['status'] === 401, 'web financial deletion requires fresh correct password');
    $webParams['password'] = $password;
    $webConfirm = webDeletion('confirm', $webParams);
    check($webConfirm['status'] === 200 && str_contains($webConfirm['html'], 'Account deleted.'), 'web policy3 confirms reviewed linked deletion and transfer');
    $webReplay = webDeletion('confirm', $webParams);
    check($webReplay['status'] === 200 && str_contains($webReplay['html'], 'Account deleted.'), 'lost web response replay resolves original receipt after bearer deletion');
    $webRecord = array_values(array_filter(data(call('finance2.pull', ['scopeId'=>$webOrg, 'cursor'=>0, 'linkedPaymentsAware'=>true], $e))['records'], fn($r)=>$r['id']===$webExpense))[0];
    $webRetainedPayment = data(call('finance3.payments', ['scopeId'=>$webOrg], $e))['events'][0];
    check(!$webRecord['deleted'] && $webRecord['payload']['amountMinor'] === 3000 && $webRecord['payload']['payerAccountId'] === null && $webRetainedPayment['eventId'] === $webEvent['eventId'] && $webRetainedPayment['reimbursements'][0]['amountMinor'] === 1000 && $webRetainedPayment['paidAt'] === $stamp && $webRetainedPayment['reimbursements'][0]['paidAt'] === $stamp, 'web transfer retains narrow shared expense and approved payment/refund amounts and dates');
} finally {
    unlink($webCookies);
}
