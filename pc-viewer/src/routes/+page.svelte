<script>
	import { store } from '$lib/auction/store.svelte.js';
	import { openAuctionFolder } from '$lib/auction/index.js';
	import { goto } from '$app/navigation';

	async function handleOpen() {
		await openAuctionFolder();
		if (store.auction) goto('/review');
	}
</script>

<div class="home">
	{#if store.auction}
		<div class="card">
			<h2>{store.auction.name}</h2>
			<p class="meta">
				{store.auction.lots.length} lots
				· imported {new Date(store.auction.imported_at).toLocaleDateString()}
			</p>
			<div class="actions">
				<a href="/review" class="btn btn-primary">Continue to Review →</a>
				<button class="btn btn-secondary" onclick={handleOpen}>Open Different Folder</button>
			</div>
		</div>
	{:else}
		<div class="card center">
			<h1>Lot Builder</h1>
			<p>Open an auction folder transferred from your phone to get started.</p>
			<button class="btn btn-primary btn-lg" onclick={handleOpen} disabled={store.loading}>
				{store.loading ? 'Loading…' : 'Open Auction Folder'}
			</button>
			{#if store.error}
				<p class="error">{store.error}</p>
			{/if}
		</div>
	{/if}
</div>

<style>
	.home {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: calc(100vh - 52px - 3rem);
	}

	.card {
		background: #fff;
		border-radius: 10px;
		padding: 2.5rem 3rem;
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
		max-width: 440px;
		width: 100%;
	}

	.card.center {
		text-align: center;
	}

	h1 {
		font-size: 1.8rem;
		font-weight: 700;
		margin: 0 0 0.5rem;
	}

	h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 0.25rem;
	}

	p {
		color: #555;
		margin: 0 0 1.75rem;
		font-size: 1rem;
		line-height: 1.5;
	}

	.meta {
		font-size: 0.875rem;
		color: #777;
		margin-bottom: 1.5rem;
	}

	.actions {
		display: flex;
		gap: 0.75rem;
		flex-wrap: wrap;
	}

.btn {
		padding: 0.5rem 1.25rem;
		border-radius: 6px;
		border: none;
		font-size: 0.9rem;
		font-weight: 500;
		cursor: pointer;
		text-decoration: none;
		display: inline-block;
		transition: opacity 0.1s, background 0.1s;
	}

	.btn:disabled {
		opacity: 0.5;
		cursor: default;
	}

	.btn-primary {
		background: #2563eb;
		color: #fff;
	}

	.btn-primary:hover:not(:disabled) {
		background: #1d4ed8;
	}

	.btn-secondary {
		background: #f3f4f6;
		color: #374151;
	}

	.btn-secondary:hover {
		background: #e5e7eb;
	}

	.btn-lg {
		padding: 0.7rem 2rem;
		font-size: 1rem;
	}

	.error {
		color: #dc2626;
		font-size: 0.85rem;
		margin-top: 1rem;
		margin-bottom: 0;
	}
</style>
