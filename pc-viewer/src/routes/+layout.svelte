<script>
	import { store } from '$lib/auction/store.svelte.js';

	let { children } = $props();
</script>

<svelte:head>
	<title>Lot Builder</title>
</svelte:head>

<nav>
	<a class="brand" href="/">Lot Builder</a>
	<div class="nav-links">
		<a href="/" class="nav-link">Home</a>
		{#if store.auction}
			<a href="/review" class="nav-link">Review ({store.auction.lots.length})</a>
		{:else}
			<span class="nav-link disabled">Review</span>
		{/if}
		<span class="nav-link disabled">Analyze</span>
		<span class="nav-link disabled">Upload</span>
	</div>
	{#if store.auction}
		<span class="auction-name">{store.auction.name}</span>
	{/if}
</nav>

<main>
	{@render children()}
</main>

<style>
	:global(*, *::before, *::after) { box-sizing: border-box; }
	:global(body) {
		margin: 0;
		font-family: system-ui, -apple-system, sans-serif;
		background: #f4f4f4;
		color: #1a1a1a;
	}

	nav {
		display: flex;
		align-items: center;
		gap: 1.5rem;
		padding: 0 1.5rem;
		height: 52px;
		background: #1e1e1e;
		color: #fff;
		flex-shrink: 0;
	}

	.brand {
		font-weight: 700;
		font-size: 1.05rem;
		color: #fff;
		text-decoration: none;
		letter-spacing: -0.01em;
	}

	.nav-links {
		display: flex;
		gap: 0.25rem;
	}

	.nav-link {
		padding: 0.3rem 0.75rem;
		border-radius: 4px;
		font-size: 0.875rem;
		color: #ccc;
		text-decoration: none;
		transition: background 0.1s, color 0.1s;
	}

	a.nav-link:hover {
		background: rgba(255, 255, 255, 0.1);
		color: #fff;
	}

	.nav-link.disabled {
		color: #444;
		cursor: default;
	}

	.auction-name {
		margin-left: auto;
		font-size: 0.8rem;
		color: #666;
		font-style: italic;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		max-width: 300px;
	}

	main {
		padding: 1.5rem;
		min-height: calc(100vh - 52px);
	}
</style>
