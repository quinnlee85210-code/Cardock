
window.addEventListener('load', function () {
  const byId = id => document.getElementById(id);
  const marker = name => {
    const e = document.createElement('div'); e.id = 'cardock-' + name + '-status';
    e.textContent = 'pending'; document.body.appendChild(e); return e;
  };
  const file = marker('file-reader'), editor = marker('account-editor');
  const preflight = marker('preflight'), approval = marker('approval'), disconnect = marker('disconnect');
  const reader = new FileReader();
  reader.onload = () => { file.textContent = new Uint8Array(reader.result).length === 4 ? 'ok' : 'failed'; };
  reader.readAsArrayBuffer(new File([new Uint8Array([80,75,3,4])], 'fictional.xlsx'));
  let stage = 0;
  const observer = new MutationObserver(() => {
    if (stage === 0 && !byId('workspace').hidden && !byId('new-account-button').disabled) {
      stage = 1;
      byId('new-account-button').click();
      editor.textContent = !byId('account-editor').hidden ? 'ok' : 'failed';
      byId('cancel-account-button').click();
      byId('batch-import-tab').click();
      const transfer = new DataTransfer();
      transfer.items.add(new File(['platformName\nBrowser fixture'], 'fictional.csv', {type:'text/csv'}));
      byId('batch-drop-zone').dispatchEvent(new DragEvent('drop', {dataTransfer:transfer,bubbles:true,cancelable:true}));
    } else if (stage === 1 && !byId('batch-table-region').hidden && !byId('new-account-button').disabled) {
      stage = 2;
      byId('batch-commit-button').click();
      preflight.textContent = !byId('batch-commit-button').disabled && document.activeElement === byId('batch-final-confirm') ? 'ok' : 'failed';
      byId('batch-final-confirm').checked = true;
      byId('batch-final-confirm').dispatchEvent(new Event('change', {bubbles:true}));
      byId('batch-commit-button').click();
    } else if (stage === 2 && byId('phone-approval-dialog').open) {
      stage = 3; approval.textContent = 'ok';
    } else if (stage === 3 && byId('workspace').hidden) {
      stage = 4;
      disconnect.textContent = byId('batch-table-body').children.length === 0 && byId('account-password').value === '' ? 'ok' : 'failed';
      observer.disconnect();
    }
  });
  observer.observe(document.body, {attributes:true,childList:true,subtree:true});
  byId('connection-code').value = new URL(location.href).searchParams.get('code') || '';
  byId('pair-button').click();
});
