// Reads an equipment item's barcode from the camera's picture with ZXing's WebAssembly
// reader (assets/vendor/zxing_reader.js, zxing-wasm 3.1.5). The .wasm file is served
// from our own assets, never the library's default CDN.
import {prepareZXingModule, readBarcodes} from "../vendor/zxing_reader"
import wasmUrl from "../vendor/zxing_reader.wasm"

prepareZXingModule({
  overrides: {locateFile: (path, prefix) => (path.endsWith(".wasm") ? wasmUrl : prefix + path)},
})

// Every format ZXing reads. South Fraser's labels are mostly QR, some Code 128, and
// Andrew wants any barcode read (2026-10-11).
const FORMATS = ["AllReadable"]

export async function read(image) {
  const [found] = await readBarcodes(image, {formats: FORMATS, maxNumberOfSymbols: 1})
  return found?.text || null
}
