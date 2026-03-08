/**
 * AuctionWorx Upload Adapter
 *
 * Implements the uploadAuction() interface for AuctionWorx.
 *
 * Upload sequence per lot:
 *   1. Upload each image to AW media pool → receive UUID
 *   2. Write platform_uuid per image to auctionJson
 *   3. Create lot in AW with title, description, image UUIDs
 *   4. Write platform_lot_id to auctionJson
 *   5. Set lot status → 'uploaded'
 *
 * Safe to re-run: checks platform_uuid and platform_lot_id before creating anything.
 */

/** @param {Object} auctionJson @param {string} folderPath @param {Object} config @param {Function} onProgress */
export async function uploadAuction(auctionJson, folderPath, config, onProgress) {
  // TODO: implement AuctionWorx upload
  // Confirm with AW before building:
  //   - Does lot creation accept external image URLs, or must images be pre-uploaded for UUIDs?
  //   - Rate limits on media upload endpoint?
  //   - Auth method: API key header, OAuth, or session token?
  //   - Endpoint for creating auction vs. adding lots to existing auction?
  throw new Error('AuctionWorx adapter not yet implemented');
}
