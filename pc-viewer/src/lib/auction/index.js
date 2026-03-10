import { store } from './store.svelte.js';

// Runtime cache for blob URLs — not persisted, rebuilt each session
const urlCache = new Map();

function genId() {
	return 'lot_' + Math.random().toString(36).slice(2, 9);
}

// ---------------------------------------------------------------------------
// Open folder + import
// ---------------------------------------------------------------------------

export async function openAuctionFolder() {
	store.loading = true;
	store.error = null;

	try {
		const handle = await window.showDirectoryPicker({ mode: 'readwrite' });
		store.folderHandle = handle;
		store.sessionHandles = {};
		urlCache.clear();

		// Walk directory — collect session subfolders
		const sessionDirs = [];
		for await (const [name, entry] of handle.entries()) {
			if (entry.kind === 'directory') {
				store.sessionHandles[name] = entry;
				try {
					const sf = await entry.getFileHandle('session.json');
					const file = await sf.getFile();
					const session = JSON.parse(await file.text());
					sessionDirs.push({ folder: name, session });
				} catch {
					// Not a session folder — skip
				}
			}
		}

		// Sort sessions chronologically (timestamp-first folder names)
		sessionDirs.sort((a, b) => a.folder.localeCompare(b.folder));

		// Try to read existing auction.json
		let auctionJson = null;
		try {
			const af = await handle.getFileHandle('auction.json');
			const file = await af.getFile();
			auctionJson = JSON.parse(await file.text());
		} catch {
			// No auction.json yet
		}

		if (auctionJson?.lots) {
			// Resume existing PC-side auction
			store.auction = auctionJson;
		} else {
			// Fresh import — build from session files
			const name = auctionJson?.name || handle.name;
			const createdAt = auctionJson?.created_at || new Date().toISOString();

			const lots = [];
			for (const { folder, session } of sessionDirs) {
				for (const lot of session.lots) {
					lots.push({
						id: genId(),
						images: lot.images.map(filename => ({ filename, session: folder })),
						notes: lot.notes || '',
						status: 'captured'
					});
				}
			}

			store.auction = {
				name,
				created_at: createdAt,
				imported_at: new Date().toISOString(),
				lots
			};

			await saveAuction();
		}
	} catch (e) {
		if (e.name !== 'AbortError') {
			store.error = e.message;
		}
	} finally {
		store.loading = false;
	}
}

// ---------------------------------------------------------------------------
// Persist
// ---------------------------------------------------------------------------

export async function saveAuction() {
	if (!store.folderHandle || !store.auction) return;

	const toSave = {
		name: store.auction.name,
		created_at: store.auction.created_at,
		imported_at: store.auction.imported_at,
		lots: store.auction.lots.map(lot => ({
			id: lot.id,
			images: lot.images.map(img => ({ filename: img.filename, session: img.session })),
			notes: lot.notes,
			status: lot.status,
			...(lot.ai_title !== undefined       && { ai_title: lot.ai_title }),
			...(lot.ai_description !== undefined  && { ai_description: lot.ai_description }),
			...(lot.title !== undefined           && { title: lot.title }),
			...(lot.description !== undefined     && { description: lot.description }),
			...(lot.platform_lot_id !== undefined && { platform_lot_id: lot.platform_lot_id })
		}))
	};

	const fh = await store.folderHandle.getFileHandle('auction.json', { create: true });
	const writable = await fh.createWritable();
	await writable.write(JSON.stringify(toSave, null, 2));
	await writable.close();
}

// ---------------------------------------------------------------------------
// Image URL resolution
// ---------------------------------------------------------------------------

export async function getImageUrl(filename, session) {
	const key = `${session}/${filename}`;
	if (urlCache.has(key)) return urlCache.get(key);

	const sessionHandle = store.sessionHandles[session];
	if (!sessionHandle) return null;

	try {
		const fh = await sessionHandle.getFileHandle(filename);
		const file = await fh.getFile();
		const url = URL.createObjectURL(file);
		urlCache.set(key, url);
		return url;
	} catch {
		return null;
	}
}

// ---------------------------------------------------------------------------
// Lot operations — all mutate store.auction and call saveAuction()
// ---------------------------------------------------------------------------

export async function reorderLots(fromIndex, toIndex) {
	const lots = [...store.auction.lots];
	const [lot] = lots.splice(fromIndex, 1);
	lots.splice(toIndex, 0, lot);
	store.auction.lots = lots;
	await saveAuction();
}

export async function deleteLot(index) {
	store.auction.lots = store.auction.lots.filter((_, i) => i !== index);
	await saveAuction();
}

export async function splitLot(lotIndex, splitAt) {
	const lot = store.auction.lots[lotIndex];
	if (splitAt <= 0 || splitAt >= lot.images.length) return;

	const lots = [...store.auction.lots];
	const a = { ...lot, id: genId(), images: lot.images.slice(0, splitAt) };
	const b = { ...lot, id: genId(), images: lot.images.slice(splitAt), notes: '' };
	lots.splice(lotIndex, 1, a, b);
	store.auction.lots = lots;
	await saveAuction();
}

export async function mergeLots(index) {
	if (index >= store.auction.lots.length - 1) return;

	const lots = [...store.auction.lots];
	const a = lots[index];
	const b = lots[index + 1];
	const merged = {
		...a,
		images: [...a.images, ...b.images],
		notes: [a.notes, b.notes].filter(Boolean).join(' | ')
	};
	lots.splice(index, 2, merged);
	store.auction.lots = lots;
	await saveAuction();
}

export async function deleteImage(lotIndex, imageIndex) {
	const lots = [...store.auction.lots];
	const lot = { ...lots[lotIndex], images: [...lots[lotIndex].images] };
	lot.images.splice(imageIndex, 1);

	if (lot.images.length === 0) {
		lots.splice(lotIndex, 1);
	} else {
		lots[lotIndex] = lot;
	}

	store.auction.lots = lots;
	await saveAuction();
}

export async function reorderImages(lotIndex, fromIndex, toIndex) {
	const lots = [...store.auction.lots];
	const lot = { ...lots[lotIndex], images: [...lots[lotIndex].images] };
	const [img] = lot.images.splice(fromIndex, 1);
	lot.images.splice(toIndex, 0, img);
	lots[lotIndex] = lot;
	store.auction.lots = lots;
	await saveAuction();
}

// toImageIndex = null means append to end of target lot
export async function moveImage(fromLotIndex, imageIndex, toLotIndex, toImageIndex = null) {
	const lots = store.auction.lots.map(l => ({ ...l, images: [...l.images] }));
	const [img] = lots[fromLotIndex].images.splice(imageIndex, 1);

	if (toImageIndex !== null) {
		lots[toLotIndex].images.splice(toImageIndex, 0, img);
	} else {
		lots[toLotIndex].images.push(img);
	}

	// Remove lots that became empty after a move
	store.auction.lots = lots.filter(l => l.images.length > 0);
	await saveAuction();
}
