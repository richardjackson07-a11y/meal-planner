/**
 * Jackson Family Meal Planner — shared storage backend.
 *
 * Paste this into a Google Apps Script project bound to a Google Sheet,
 * then deploy it as a Web app (Execute as: Me, Who has access: Anyone).
 * The app talks to it with plain POST requests; see SETUP.md.
 *
 * Each household is one row: code | rev | updated | json
 * `rev` is a revision counter used to detect two phones writing at once.
 */

var SHEET_NAME = 'households';

function doGet(e) {
  // Handy for a browser sanity check: .../exec?action=ping
  return handle(e && e.parameter ? e.parameter : {});
}

function doPost(e) {
  var body = {};
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return out({ error: 'body was not valid JSON' });
  }
  return handle(body);
}

function handle(req) {
  var action = String(req.action || 'pull');

  if (action === 'ping') {
    return out({ ok: true, service: 'meal-planner', time: new Date().toISOString() });
  }

  var code = String(req.code || '').trim().toLowerCase();
  if (!code) return out({ error: 'missing household code' });
  if (code.length > 60) return out({ error: 'household code too long' });

  // One writer at a time, so two phones saving together cannot clobber the row.
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(20000);
  } catch (err) {
    return out({ error: 'busy, try again' });
  }

  try {
    var sh = getSheet();
    var found = findRow(sh, code);

    if (action === 'pull') {
      if (!found) return out({ rev: 0, doc: null });
      return out({ rev: found.rev, doc: JSON.parse(found.json) });
    }

    if (action === 'push') {
      var baseRev = Number(req.rev || 0);
      if (found && found.rev !== baseRev) {
        // The other phone got here first. Hand back what is stored so the
        // app can merge and try again.
        return out({ conflict: true, rev: found.rev, doc: JSON.parse(found.json) });
      }
      var doc = req.doc;
      if (!doc || typeof doc !== 'object') return out({ error: 'missing doc' });
      var json = JSON.stringify(doc);
      if (json.length > 4000000) return out({ error: 'document too large' });

      var newRev = (found ? found.rev : 0) + 1;
      if (found) {
        sh.getRange(found.row, 1, 1, 4).setValues([[code, newRev, new Date(), json]]);
      } else {
        sh.appendRow([code, newRev, new Date(), json]);
      }
      return out({ rev: newRev });
    }

    return out({ error: 'unknown action: ' + action });
  } finally {
    lock.releaseLock();
  }
}

function getSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(SHEET_NAME);
  if (!sh) {
    sh = ss.insertSheet(SHEET_NAME);
    sh.appendRow(['code', 'rev', 'updated', 'json']);
    sh.setFrozenRows(1);
  }
  return sh;
}

function findRow(sh, code) {
  var last = sh.getLastRow();
  if (last < 2) return null;
  var codes = sh.getRange(2, 1, last - 1, 1).getValues();
  for (var i = 0; i < codes.length; i++) {
    if (String(codes[i][0]).trim().toLowerCase() === code) {
      var row = i + 2;
      var vals = sh.getRange(row, 1, 1, 4).getValues()[0];
      return { row: row, rev: Number(vals[1]) || 0, json: vals[3] || '{}' };
    }
  }
  return null;
}

function out(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
