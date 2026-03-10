// Reactive singleton store for the current auction session.
// Import `store` anywhere — reads are reactive in Svelte 5 components.

export const store = $state({
	folderHandle: null,     // FileSystemDirectoryHandle for auction root
	sessionHandles: {},     // { folderName: FileSystemDirectoryHandle }
	auction: null,          // working auction object (built from session.json files)
	loading: false,
	error: null
});
