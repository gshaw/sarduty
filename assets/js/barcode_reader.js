// Reads an equipment item's barcode from the camera's picture with ZXing's WebAssembly
// reader (assets/vendor/zxing_reader.js, zxing-wasm 3.1.5). The .wasm file is served
// from our own assets, never the library's default CDN.
import {prepareZXingModule, readBarcodes} from "../vendor/zxing_reader"
import wasmUrl from "../vendor/zxing_reader.wasm"

prepareZXingModule({
  overrides: {locateFile: (path, prefix) => (path.endsWith(".wasm") ? wasmUrl : prefix + path)},
})

// South Fraser's barcodes hold lowercase letters, spaces, and "#", so Code 128 or QR is likely,
// with UPC and EAN on bought items (2026-10-11).
const FORMATS = ["Code128", "Code39", "Code93", "Codabar", "ITF", "EANUPC", "QRCode", "DataMatrix"]

export async function read(image) {
  const [found] = await readBarcodes(image, {formats: FORMATS, maxNumberOfSymbols: 1})
  return found?.text || null
}
