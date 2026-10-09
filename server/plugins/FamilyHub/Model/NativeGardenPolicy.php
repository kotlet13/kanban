<?php
namespace Kanboard\Plugin\FamilyHub\Model;
/** Exact format-2 garden document. Calendar dates are not delivery instants. */

class NativeGardenPolicy extends NativeDatabase
{

    public function validate($p, $scope, $current)
    {
        if (!is_array($p)
            || array_is_list($p)
            || strlen(json_encode($p, JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR))>524288
            || ($this->one('SELECT kind FROM familyhub_scopes WHERE id=?', [$scope])['kind'] ?? '') !== 'household') {
            throw new NativeError('validation_error');
        }
        $this->fields($p, ['version', 'id', 'name', 'notes', 'areas', 'seasons', 'revision', 'createdAt', 'updatedAt']);
        if ($p['version'] !== 2 || !is_int($p['revision']) || $p['revision']<0) {
            throw new NativeError('validation_error');
        }
        $this->uuid($p['id']);
        $this->string($p['name'], 200, false);
        $this->string($p['notes'], 20000);
        $dates = new NativeRecordPolicy($this->container);
        $dates->date($p['createdAt']);
        $dates->date($p['updatedAt']);
        if (new \DateTimeImmutable($p['updatedAt'])<new \DateTimeImmutable($p['createdAt'])) {
            throw new NativeError('invalid_date_range');
        }
        if ($current && new \DateTimeImmutable(json_decode($current['payload'], true, 32, JSON_THROW_ON_ERROR)['createdAt']) != new \DateTimeImmutable($p['createdAt'])) {
            throw new NativeError('created_at_immutable');
        }
        $this->list($p['areas'], 1000);
        $this->list($p['seasons'], 500);
        $areaIds = [];
        $plantingIds = [];
        $years = [];
        $count = 0;
        foreach ($p['areas'] as $a) {
            if (!is_array($a)) {
                throw new NativeError('validation_error');
            }
            $this->fields($a, ['id', 'label', 'x', 'y', 'width', 'height', 'kind', 'archived']);
            $this->id($a['id']);
            $this->string($a['label'], 200, false);
            if (isset($areaIds[$a['id']]) || !in_array($a['kind'], ['bed', 'zone'], true) || !is_bool($a['archived'])) {
                throw new NativeError('validation_error');
            }
            $areaIds[$a['id']] = true;
            foreach (['x', 'y', 'width', 'height'] as $key) {
                if ((!is_int($a[$key]) && !is_float($a[$key])) || !is_finite((float)$a[$key]) || $a[$key]<0 || $a[$key]>1) {
                    throw new NativeError('validation_error');
                }
            }
            if ($a['width'] <= 0 || $a['height'] <= 0 || $a['x']+$a['width']>1 || $a['y']+$a['height']>1) {
                throw new NativeError('validation_error');
            }
        }
        foreach ($p['seasons'] as $s) {
            if (!is_array($s)) {
                throw new NativeError('validation_error');
            }
            $this->fields($s, ['year', 'notes', 'plantings']);
            $this->string($s['notes'], 20000);
            $this->list($s['plantings'], 2000);
            if (!is_int($s['year']) || $s['year']<1900 || $s['year']>9999 || isset($years[$s['year']])) {
                throw new NativeError('validation_error');
            }
            $years[$s['year']] = true;
            foreach ($s['plantings'] as $v) {
                if (!is_array($v)) {
                    throw new NativeError('validation_error');
                }
                $this->fields($v, ['id', 'areaId', 'crop', 'variety', 'family', 'status', 'notes', 'sowAt', 'plantAt', 'harvestAt']);
                $this->id($v['id']);
                $this->id($v['areaId']);
                if (!isset($areaIds[$v['areaId']])
                    || isset($plantingIds[$v['id']])
                    || isset($areaIds[$v['id']])
                    || $v['id'] === $p['id']
                    || !in_array($v['status'], ['planned', 'actual'], true)
                    || ++$count>10000) {
                    throw new NativeError('validation_error');
                }
                $plantingIds[$v['id']] = true;
                foreach (['crop', 'variety', 'family'] as $key) {
                    $this->string($v[$key], 200, $key !== 'crop');
                }
                $this->string($v['notes'], 20000);
                $previous = null;
                foreach (['sowAt', 'plantAt', 'harvestAt'] as $key) {
                    if ($v[$key] === null) {
                        continue;
                    }
                    if (!is_string($v[$key]) || !preg_match('/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/D', $v[$key]) || (int)substr($v[$key], 0, 4)<1900) {
                        throw new NativeError('validation_error');
                    }
                    $date = \DateTimeImmutable::createFromFormat('!Y-m-d', $v[$key], new \DateTimeZone('UTC'));
                    if (!$date || $date->format('Y-m-d') !== $v[$key] || ($previous !== null && strcmp($previous, $v[$key])>0)) {
                        throw new NativeError('invalid_date_range');
                    }
                    $previous = $v[$key];
                }
            }
        }
    }

    private function list($value, $maximum)
    {
        if (!is_array($value) || !array_is_list($value) || count($value)>$maximum) {
            throw new NativeError('validation_error');
        }
    }

    private function string($value, $units, $empty = true)
    {
        $this->text($value, $units*4, $empty);
        if (strlen(mb_convert_encoding($value, 'UTF-16LE', 'UTF-8'))>$units*2) {
            throw new NativeError('validation_error');
        }
    }

    private function id($value)
    {
        $this->text($value, 200);
    }
}
