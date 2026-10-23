<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Derive a bounded topic only after the worker checked recipient visibility. */
class NativePushPresentation extends NativeDatabase
{
    private function label($value)
    {
        return mb_substr(trim(preg_replace('/[\x00-\x1F\x7F]/u', ' ', (string)$value)), 0, 140);
    }

    public function topic(array $inbox, $language)
    {
        $en=$language==='en';
        if ($inbox['kind'] === NativeCryptoInvitationNotificationV2::KIND) {
            return ['title'=>$en?'Invitation accepted':'Povabilo sprejeto',
                'body'=>$en?'The recipient accepted your invitation. Confirm access.':'Prejemnik je sprejel vaše povabilo. Potrdite dostop.'];
        }
        if (str_starts_with($inbox['kind'],'crypto2.')) {
            return ['title'=>$inbox['kind']==='crypto2.reminder.due' ? ($en?'Reminder':'Opomnik') : ($en?'Jivie update':'Obvestilo Jivie'), 'body'=>$en?'Open Jivie to view the encrypted content.':'Odprite Jivie za ogled šifrirane vsebine.'];
        }
        $scope=$this->one('SELECT name FROM familyhub_scopes WHERE id=?',[$inbox['scope_id']]);
        $row=$this->one('SELECT payload,deleted FROM familyhub_records WHERE scope_id=? AND id=? AND type=?',[$inbox['scope_id'],$inbox['target_id'],$inbox['target_type']]);
        $payload=$row && !(int)$row['deleted'] ? json_decode($row['payload'],true) : [];
        $name=$this->label($payload['title']??($payload['name']??''));
        $kind=$inbox['kind'];
        $title=match($kind) {
            'task.assigned'=>$en?'Task assigned to you':'Dodeljeno vam je opravilo',
            'task.created'=>$en?'Task added':'Dodano opravilo',
            'task.completed'=>$en?'Task completed':'Opravilo zaključeno',
            'shoppingItem.created'=>$en?'Item added to shopping list':'Dodan izdelek na nakupovalni seznam',
            'shoppingItem.checked'=>$en?'Shopping item marked bought':'Izdelek označen kot kupljen',
            'shoppingList.created'=>$en?'Shopping list added':'Dodan nakupovalni seznam',
            'member.joined'=>$en?'New member':'Nov član prostora',
            'idea.created'=>$en?'Idea added':'Dodana ideja',
            'reminder.due'=>$en?'Reminder':'Opomnik',
            default=>str_ends_with($kind,'.deleted') ? ($en?'Item deleted':'Zapis izbrisan') : match($inbox['target_type']) {
                'task'=>$en?'Task changed':'Sprememba na opravilu',
                'project'=>$en?'Project changed':'Sprememba na projektu',
                'idea'=>$en?'Idea changed':'Sprememba ideje',
                'event'=>$en?'Calendar event changed':'Sprememba dogodka',
                'shoppingItem','shoppingList'=>$en?'Shopping list changed':'Sprememba nakupovalnega seznama',
                default=>$en?'Space updated':'Sprememba v prostoru',
            },
        };
        $details=$this->label($scope['name']??'');
        if ($inbox['target_type']==='shoppingItem') {
            $list=$this->shoppingContextRecord($inbox,$row);
            $listName=$list ? $this->label(json_decode($list['payload'],true)['title']??'') : '';
            if ($listName!=='') $title.=' · '.$listName;
            if ($name!=='') $details=$name.($details!==''?' · '.$details:'');
        } elseif ($name!=='') {
            $title.=' · '.$name;
        }
        return ['title'=>$this->label($title),'body'=>$this->label($details)];
    }
}
