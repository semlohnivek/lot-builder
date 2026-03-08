/**
 * Upload Adapter Interface
 *
 * Every platform adapter must export this function with this exact signature.
 *
 * @param {Object}   auctionJson  - the full auction.json object
 * @param {string}   folderPath   - absolute path to the auction folder (for reading images)
 * @param {Object}   config       - platform credentials from config.json adapters[name]
 * @param {Function} onProgress   - callback(lotId, step, status) for UI updates
 * @returns {Object}              - updated auctionJson with platform IDs populated
 */
export async function uploadAuction(auctionJson, folderPath, config, onProgress) {
  throw new Error('uploadAuction() must be implemented by the adapter');
}
