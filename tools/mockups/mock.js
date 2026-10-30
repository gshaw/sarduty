// Mockup kit: what the app's hooks would do once connected, so a static page looks live.
// The Select all box shows its rows' state.
document.querySelectorAll('th input[aria-label="Select all"]').forEach(head => {
  const boxes = [...head.closest("table").querySelectorAll('tbody input[type="checkbox"]')];
  const n = boxes.filter(b => b.checked).length;
  head.checked = n > 0 && n === boxes.length;
  head.indeterminate = n > 0 && n < boxes.length;
});
document.querySelectorAll("#client-error, #server-error").forEach(t => t.hidden = true);
