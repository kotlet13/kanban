<div class="page-header"><h2>FamilyHub — prijave / Reports</h2></div>
<p>Prijave prejmejo skrbniki tega strežnika. Preglejte omejeni posnetek in navedite razlog odločitve. / This server's administrators receive these private reports. Review the limited snapshot and record your decision reason.</p>
<p>Finance: ohranite zgodovino; uporabite običajen, upravičen popravek v aplikaciji. Omejitev člana velja za izbrani prostor, ne njegov osebni račun. / Preserve financial history; use an authorized normal correction. Member restrictions apply to the selected space, including its inherited access, and preserve personal accounts.</p>
<?php if ($error): ?><p class="alert alert-error"><?= $this->text->e($error) ?></p><?php endif ?>
<?php foreach ($reports as $report): ?>
<section class="panel"><h3><?= $this->text->e($report['target_type'].' · '.$report['reason'].' · '.$report['status']) ?></h3>
<p><?= $this->text->e($report['id'].' / '.gmdate('Y-m-d H:i:s',(int)$report['created_at'])) ?></p>
<pre style="white-space:pre-wrap;overflow-wrap:anywhere"><?= $this->text->e($report['snapshot']??'Evidence expired after resolution retention period') ?></pre>
<p style="white-space:pre-wrap;overflow-wrap:anywhere"><?= $this->text->e($report['details']??'') ?></p>
<?php foreach ($report['audit'] as $audit): ?><p><?= $this->text->e($audit['action'].' / '.gmdate('Y-m-d H:i:s',(int)$audit['created_at']).' / '.$audit['note']) ?></p><?php endforeach ?>
<form method="post" action="<?= $this->url->href('ModerationController','review',['plugin'=>'FamilyHub']) ?>">
<?= $this->form->csrf() ?>
<input type="hidden" name="reportId" value="<?= $this->text->e($report['id']) ?>">
<input type="hidden" name="reviewRevision" value="<?= (int)$report['review_revision'] ?>">
<input type="hidden" name="targetRevision" value="<?= (int)$report['target_revision'] ?>">
<label>Razlog / Decision reason <textarea name="note" required maxlength="2000"></textarea></label>
<select name="decision"><option value="reviewed">Pregledano / Reviewed</option><option value="resolved">Rešeno / Resolved</option><option value="dismissed">Zavrnjeno / Dismissed</option>
<?php if ($report['target_type']==='record' && $report['redacted_at']===null): ?><option value="remove_content">Odstrani prikazani zapis / Remove shown record (revision checked)</option><?php endif ?>
<?php if ($report['target_type']==='user' && $report['redacted_at']===null): ?><option value="restrict_member">Omeji člana tega prostora / Restrict member in this space</option><?php endif ?>
<?php if ($report['target_type']==='user'): ?><option value="unrestrict_member">Odstrani omejitev / Undo space restriction (existing membership required)</option><?php endif ?>
</select><label><input type="checkbox" name="confirmation" value="APPLY"> Izrecno potrjujem odstranitev besedila ali spremembo omejitve prikazane tarče / I explicitly confirm removal or access restriction changes for the shown target</label><button type="submit" class="btn btn-blue">Shrani odločitev / Save decision</button></form></section>
<?php endforeach ?>
<?php if (!$reports): ?><p>Ni prijav / No reports</p><?php endif ?>
<?php if ($page>0): ?><?= $this->url->link('Previous','ModerationController','index',['plugin'=>'FamilyHub','page'=>$page-1]) ?><?php endif ?>
<?php if ($hasNext): ?><?= $this->url->link('Next','ModerationController','index',['plugin'=>'FamilyHub','page'=>$page+1]) ?><?php endif ?>
