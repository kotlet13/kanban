<div class="page-header"><h2>FamilyHub — prvi račun / first account</h2></div>
<p>Izrecno izdajte enkratno kodo za prvi račun v aplikaciji. Ne vključuje skrbniškega gesla; novi račun je običajen uporabnik. Veljavnost 15 minut. / Explicitly issue a single-use first-account code. Valid for 15 minutes; the new account is a regular app user.</p>
<?php if ($error): ?><p class="alert alert-error"><?= $this->text->e($error) ?></p><?php endif ?>
<?php if ($issued): ?>
    <p>To kodo varno prenesite v svojo aplikacijo; prikazana je samo pri tej izdaji. / Transfer this code privately to your app; shown only on issuance.</p>
    <pre><?= $this->text->e($issued['code']) ?></pre>
    <p>Expires (UTC): <?= $this->text->e(gmdate('Y-m-d H:i:s', $issued['expiresAt'])) ?></p>
<?php endif ?>
<?php if ($available): ?>
    <form method="post" action="<?= $this->url->href('EnrollmentController', 'issue', ['plugin' => 'FamilyHub']) ?>">
        <?= $this->form->csrf() ?>
        <input type="hidden" name="issuanceId" value="<?= $this->text->e($issuanceId) ?>">
        <button type="submit" class="btn btn-blue">Izdaj novo kodo / Issue new code</button>
    </form>
<?php else: ?><p>Enrollment is closed. Existing accounts use normal login; administrators must explicitly enable the Native API before first setup.</p><?php endif ?>
