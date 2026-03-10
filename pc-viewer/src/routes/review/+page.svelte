<script>
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { store } from '$lib/auction/store.svelte.js';
	import {
		saveAuction,
		getImageUrl,
		reorderLots,
		deleteLot,
		splitLot,
		mergeLots,
		deleteImage,
		moveImage
	} from '$lib/auction/index.js';

	$effect(() => {
		if (browser && !store.auction) goto('/');
	});

	// ---------------------------------------------------------------------------
	// Lot drag-and-drop (reorder cards via drag handle)
	// ---------------------------------------------------------------------------

	let dragLotIndex = $state(null);
	let dragOverLotIndex = $state(null);

	function onLotDragStart(e, index) {
		dragLotIndex = index;
		e.dataTransfer.effectAllowed = 'move';
		e.dataTransfer.setData('lot-card', String(index));
	}

	function onLotDragEnd() {
		dragLotIndex = null;
		dragOverLotIndex = null;
	}

	// ---------------------------------------------------------------------------
	// Image drag-and-drop (reorder within lot / move between lots)
	// ---------------------------------------------------------------------------

	let dragImageSrc = $state(null); // { lotIndex, imageIndex }
	let dragOverImage = $state(null); // { lotIndex, imageIndex }
	let dragOverCard = $state(null);  // lotIndex — image hovering over card body

	function onImageDragStart(e, lotIndex, imageIndex) {
		e.stopPropagation();
		dragImageSrc = { lotIndex, imageIndex };
		e.dataTransfer.effectAllowed = 'move';
		e.dataTransfer.setData('lot-image', JSON.stringify({ lotIndex, imageIndex }));
	}

	function onImageDragOver(e, lotIndex, imageIndex) {
		if (!hasType(e, 'lot-image')) return;
		e.preventDefault();
		e.stopPropagation();
		dragOverImage = { lotIndex, imageIndex };
		dragOverCard = null;
	}

	function onImageDrop(e, toLotIndex, toImageIndex) {
		if (!hasType(e, 'lot-image')) return;
		e.preventDefault();
		e.stopPropagation();
		if (!dragImageSrc) return;
		const { lotIndex: fromLot, imageIndex: fromImg } = dragImageSrc;
		if (fromLot === toLotIndex && fromImg === toImageIndex) { resetImageDrag(); return; }
		moveImage(fromLot, fromImg, toLotIndex, toImageIndex);
		resetImageDrag();
	}

	function onImageDragEnd() {
		resetImageDrag();
	}

	function resetImageDrag() {
		dragImageSrc = null;
		dragOverImage = null;
		dragOverCard = null;
	}

	// ---------------------------------------------------------------------------
	// Card drag-over / drop — handles both lot reorder and image-to-card drop
	// ---------------------------------------------------------------------------

	function onCardDragOver(e, index) {
		const types = Array.from(e.dataTransfer.types);
		if (types.includes('lot-card') && dragLotIndex !== null && dragLotIndex !== index) {
			e.preventDefault();
			dragOverLotIndex = index;
		} else if (types.includes('lot-image') && dragImageSrc?.lotIndex !== index) {
			e.preventDefault();
			dragOverCard = index;
		}
	}

	function onCardDrop(e, index) {
		const types = Array.from(e.dataTransfer.types);
		if (types.includes('lot-card') && dragLotIndex !== null && dragLotIndex !== index) {
			e.preventDefault();
			reorderLots(dragLotIndex, index);
			dragLotIndex = null;
			dragOverLotIndex = null;
		} else if (types.includes('lot-image') && dragImageSrc) {
			e.preventDefault();
			const { lotIndex: fromLot, imageIndex: fromImg } = dragImageSrc;
			if (fromLot !== index) moveImage(fromLot, fromImg, index, null);
			resetImageDrag();
		}
	}

	function onCardDragLeave(e, index) {
		if (!e.currentTarget.contains(e.relatedTarget)) {
			if (dragOverLotIndex === index) dragOverLotIndex = null;
			if (dragOverCard === index) dragOverCard = null;
		}
	}

	function hasType(e, type) {
		return Array.from(e.dataTransfer.types).includes(type);
	}

	// ---------------------------------------------------------------------------
	// Split mode
	// ---------------------------------------------------------------------------

	let splitMode = $state(null); // lotIndex currently in split mode

	function startSplit(lotIndex) { splitMode = lotIndex; }
	function cancelSplit() { splitMode = null; }

	async function doSplit(lotIndex, splitAt) {
		await splitLot(lotIndex, splitAt);
		splitMode = null;
	}

	// ---------------------------------------------------------------------------
	// Confirm actions
	// ---------------------------------------------------------------------------

	async function doMerge(index) {
		if (confirm(`Merge lot ${index + 1} with lot ${index + 2}?`)) {
			await mergeLots(index);
		}
	}

	async function doDelete(index) {
		if (confirm(`Delete lot ${index + 1} and all its images?`)) {
			await deleteLot(index);
		}
	}

	// ---------------------------------------------------------------------------
	// Notes — debounced autosave
	// ---------------------------------------------------------------------------

	const noteTimers = {};

	function handleNotesInput(lotIndex, value) {
		store.auction.lots[lotIndex].notes = value;
		clearTimeout(noteTimers[lotIndex]);
		noteTimers[lotIndex] = setTimeout(() => saveAuction(), 1000);
	}
</script>

{#if store.auction}
	<div class="review-header">
		<div class="title-row">
			<h1>{store.auction.name}</h1>
			<span class="lot-count">{store.auction.lots.length} lots</span>
		</div>
		<p class="hint">
			Drag <strong>⠿</strong> to reorder lots · Drag images to reorder or move between lots ·
			Hover image for <strong>×</strong> delete
		</p>
	</div>

	<div class="lot-grid">
		{#each store.auction.lots as lot, i (lot.id)}
			<div
				class="lot-card"
				class:drag-over-lot={dragOverLotIndex === i}
				class:image-drop-target={dragOverCard === i}
				ondragover={(e) => onCardDragOver(e, i)}
				ondrop={(e) => onCardDrop(e, i)}
				ondragleave={(e) => onCardDragLeave(e, i)}
				role="listitem"
			>
				<!-- Card header -->
				<div class="card-header">
					<span class="lot-num">Lot {i + 1}</span>
					<span
						class="drag-handle"
						draggable="true"
						title="Drag to reorder"
						ondragstart={(e) => onLotDragStart(e, i)}
						ondragend={onLotDragEnd}
						role="button"
						tabindex="-1"
					>⠿</span>
					<button class="btn-icon danger" onclick={() => doDelete(i)} title="Delete lot">×</button>
				</div>

				<!-- Image strip -->
				<div class="image-strip">
					{#if splitMode === i}
						<!-- Split mode: images with clickable dividers between them -->
						{#each lot.images as img, j}
							{#if j > 0}
								<button class="split-divider" onclick={() => doSplit(i, j)} title="Split here">✂</button>
							{/if}
							{#await getImageUrl(img.filename, img.session)}
								<div class="thumb"><div class="thumb-placeholder loading"></div></div>
							{:then url}
								<div class="thumb split-thumb">
									{#if url}
										<img src={url} alt="Lot {i + 1} image {j + 1}" />
									{:else}
										<div class="thumb-placeholder error">?</div>
									{/if}
								</div>
							{/await}
						{/each}
					{:else}
						<!-- Normal mode: draggable images -->
						{#each lot.images as img, j}
							<div
								class="thumb"
								class:drag-over-img={dragOverImage?.lotIndex === i && dragOverImage?.imageIndex === j}
								draggable="true"
								ondragstart={(e) => onImageDragStart(e, i, j)}
								ondragover={(e) => onImageDragOver(e, i, j)}
								ondrop={(e) => onImageDrop(e, i, j)}
								ondragend={onImageDragEnd}
								role="button"
								tabindex="-1"
							>
								{#await getImageUrl(img.filename, img.session)}
									<div class="thumb-placeholder loading"></div>
								{:then url}
									{#if url}
										<img src={url} alt="Lot {i + 1} image {j + 1}" />
									{:else}
										<div class="thumb-placeholder error">?</div>
									{/if}
								{/await}
								<button
									class="delete-img"
									onclick={() => deleteImage(i, j)}
									title="Remove image"
								>×</button>
							</div>
						{/each}
					{/if}
				</div>

				<!-- Card footer -->
				<div class="card-footer">
					<textarea
						class="notes"
						placeholder="Notes…"
						value={lot.notes}
						oninput={(e) => handleNotesInput(i, e.target.value)}
						rows="2"
					></textarea>
					<div class="card-actions">
						{#if splitMode === i}
							<button class="btn" onclick={cancelSplit}>Cancel split</button>
						{:else}
							{#if lot.images.length > 1}
								<button class="btn" onclick={() => startSplit(i)}>Split</button>
							{/if}
							{#if i < store.auction.lots.length - 1}
								<button class="btn" onclick={() => doMerge(i)}>Merge ↓</button>
							{/if}
						{/if}
					</div>
				</div>
			</div>
		{/each}
	</div>
{/if}

<style>
	.review-header {
		margin-bottom: 1.25rem;
	}

	.title-row {
		display: flex;
		align-items: baseline;
		gap: 0.75rem;
		margin-bottom: 0.25rem;
	}

	h1 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0;
	}

	.lot-count {
		font-size: 0.875rem;
		color: #777;
	}

	.hint {
		font-size: 0.8rem;
		color: #999;
		margin: 0;
	}

	/* Grid */

	.lot-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(270px, 1fr));
		gap: 0.875rem;
	}

	/* Card */

	.lot-card {
		background: #fff;
		border-radius: 8px;
		border: 2px solid transparent;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
		overflow: hidden;
		transition: border-color 0.12s, box-shadow 0.12s;
	}

	.lot-card.drag-over-lot {
		border-color: #2563eb;
		box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.15);
	}

	.lot-card.image-drop-target {
		border-color: #16a34a;
		box-shadow: 0 0 0 3px rgba(22, 163, 74, 0.15);
	}

	/* Card header */

	.card-header {
		display: flex;
		align-items: center;
		padding: 0.45rem 0.75rem;
		background: #f8f8f8;
		border-bottom: 1px solid #eee;
		gap: 0.5rem;
	}

	.lot-num {
		font-size: 0.78rem;
		font-weight: 600;
		color: #666;
		flex: 1;
	}

	.drag-handle {
		cursor: grab;
		color: #bbb;
		font-size: 1.1rem;
		user-select: none;
		padding: 0 0.25rem;
		line-height: 1;
	}

	.drag-handle:active {
		cursor: grabbing;
	}

	.btn-icon {
		background: none;
		border: none;
		cursor: pointer;
		font-size: 1rem;
		line-height: 1;
		padding: 0.15rem 0.35rem;
		border-radius: 3px;
		color: #bbb;
		transition: background 0.1s, color 0.1s;
	}

	.btn-icon.danger:hover {
		background: #fee2e2;
		color: #dc2626;
	}

	/* Image strip */

	.image-strip {
		display: flex;
		flex-wrap: nowrap;
		overflow-x: auto;
		gap: 5px;
		padding: 8px;
		min-height: 96px;
		background: #fafafa;
		align-items: center;
		scrollbar-width: thin;
	}

	.thumb {
		position: relative;
		flex-shrink: 0;
		cursor: grab;
		border-radius: 4px;
	}

	.thumb:active {
		cursor: grabbing;
	}

	.thumb img {
		height: 96px;
		width: auto;
		max-width: 130px;
		object-fit: cover;
		border-radius: 4px;
		display: block;
		pointer-events: none;
		user-select: none;
	}

	.thumb.drag-over-img img {
		outline: 2px solid #2563eb;
		outline-offset: 1px;
	}

	.split-thumb {
		cursor: default;
	}

	.thumb-placeholder {
		height: 96px;
		width: 72px;
		border-radius: 4px;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.thumb-placeholder.loading {
		background: #e9eaeb;
	}

	.thumb-placeholder.error {
		background: #fee2e2;
		color: #dc2626;
		font-weight: 700;
		font-size: 1.2rem;
	}

	.delete-img {
		position: absolute;
		top: -5px;
		right: -5px;
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: #dc2626;
		color: #fff;
		border: none;
		font-size: 0.65rem;
		line-height: 1;
		cursor: pointer;
		display: none;
		align-items: center;
		justify-content: center;
		padding: 0;
		z-index: 5;
	}

	.thumb:hover .delete-img {
		display: flex;
	}

	/* Split divider */

	.split-divider {
		background: none;
		border: 2px dashed #d1d5db;
		border-radius: 4px;
		cursor: pointer;
		padding: 0 0.5rem;
		color: #aaa;
		font-size: 1.1rem;
		height: 80px;
		display: flex;
		align-items: center;
		flex-shrink: 0;
		transition: border-color 0.1s, color 0.1s, background 0.1s;
	}

	.split-divider:hover {
		border-color: #2563eb;
		color: #2563eb;
		background: #eff6ff;
	}

	/* Card footer */

	.card-footer {
		padding: 0.6rem 0.75rem;
		border-top: 1px solid #eee;
	}

	.notes {
		width: 100%;
		border: 1px solid #e5e7eb;
		border-radius: 4px;
		padding: 0.35rem 0.5rem;
		font-size: 0.8rem;
		font-family: inherit;
		resize: none;
		outline: none;
		color: #374151;
		background: #fafafa;
		margin-bottom: 0.4rem;
		transition: border-color 0.1s;
	}

	.notes:focus {
		border-color: #93c5fd;
		background: #fff;
	}

	.card-actions {
		display: flex;
		gap: 0.4rem;
	}

	.btn {
		border: none;
		border-radius: 4px;
		cursor: pointer;
		font-size: 0.75rem;
		font-weight: 500;
		padding: 0.25rem 0.65rem;
		background: #f3f4f6;
		color: #374151;
		transition: background 0.1s;
	}

	.btn:hover {
		background: #e5e7eb;
	}
</style>
