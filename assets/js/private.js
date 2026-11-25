// A tap on blurred contact details (Web.Components.Private) shows them and does nothing
// else, so a first tap on a blurred mailto: link doesn't open Mail. Capture phase, so it
// runs before the link and LiveView. The element's data-reveal is a JS command, which
// LiveView keeps across patches, so a re-render doesn't blur it again; setting the
// attribute too covers pages with no LiveView, such as /styles.
export function listenForPrivateTaps() {
  document.addEventListener("click", event => {
    const group = event.target.closest?.(".private-text")?.closest(".private[data-private=hidden]")
    if (!group) return
    event.preventDefault()
    event.stopPropagation()
    group.dataset.private = "shown"
    window.liveSocket?.execJS(group, group.dataset.reveal)
  }, true)
}
