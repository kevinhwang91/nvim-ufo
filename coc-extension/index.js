const { languages, commands, workspace, wait, CancellationTokenSource, Disposable } = require('coc.nvim')


exports.activate = async context => {
	let { logger, subscriptions } = context
	let nvim = workspace.nvim
	subscriptions.push(commands.registerCommand('ufo.foldingRange', async (bufnr, kind) => {
		let doc = workspace.getDocument(bufnr)
		if (!doc || !doc.attached) {
			await wait(50)
			doc = workspace.getDocument(bufnr)
			if (!doc || !doc.attached) {
				return
			}
		}
		let { textDocument } = doc

		// TODO
		// no way to check whether server supports `textDocument/foldingRange`
		// or server will call `client/registerCapability`
		if (!languages.hasProvider('foldingRange', textDocument)) {
			await wait(500)
			if (!languages.hasProvider('foldingRange', textDocument)) {
				throw 'UfoFallbackException'
			}
		}
		await doc.synchronize()
		let tokenSource = new CancellationTokenSource()
		let { token } = tokenSource
		let ranges = await languages.provideFoldingRanges(textDocument, {}, token)
		if (!ranges || !ranges.length) {
			return []
		}
		ranges = ranges.filter(o => (!kind || kind == o.kind) && o.startLine < o.endLine)
			.sort((a, b) => {
				if (b.startLine == a.startLine) {
					return a.endLine - b.endLine
				} else {
					return b.startLine - a.startLine
				}
			})
		return ranges
	}))
	subscriptions.push(Disposable.create(async () => {
		await nvim.lua(`require('ufo.provider.lsp.coc').handleDisposeNotify(...)`, [])
	}))
	await nvim.lua(`require('ufo.provider.lsp.coc').handleInitNotify(...)`, [])
}
