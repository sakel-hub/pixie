/**
 * Deploy code to ContentDB
 * Copyright (C) 2026 SaKeL
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

import fetch from 'node-fetch'
import dotenv from 'dotenv'
import yargs from 'yargs/yargs'
import { hideBin } from 'yargs/helpers'

const argv = yargs(hideBin(process.argv))
	.option('env', {
		alias: 'e',
		type: 'string',
		description: 'Path to custom .env file'
	})
	.option('token', {
		type: 'string',
		description: 'ContentDB API token'
	})
	.option('title', {
		type: 'string',
		description: 'Release title'
	})
	.option('tag', {
		type: 'string',
		description: 'Release tag'
	})
	.option('ref', {
		type: 'string',
		description: 'Git reference or commit'
	})
	.help()
	.argv

if (argv.env) {
	dotenv.config({ path: argv.env })
} else {
	dotenv.config()
}

try {
    const token = process.env.CONTENT_DB_PIXIE_TOKEN || process.env.CONTENT_DB_TOKEN || argv.token
    if (!token) {
        console.error('Error: Missing ContentDB token! Provide CONTENT_DB_PIXIE_TOKEN, CONTENT_DB_TOKEN, or pass --token=<token>.')
        process.exit(1)
    }

    const title = argv.title ?? argv.tag
    if (!title) {
        console.error('Error: Missing release title/tag! Pass --title=<title>.')
        process.exit(1)
    }

    const ref = argv.ref ?? title ?? 'main'

    const body = {
        method: 'git',
        title: title,
        ref: ref
    }

    console.log('Submitting release to ContentDB for SaKeL/pixie:', body)

    const response = await fetch('https://content.luanti.org/api/packages/SaKeL/pixie/releases/new/', {
        method: 'POST',
        body: JSON.stringify(body),
        headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`
        }
    })

    const data = await response.json()
    console.log('ContentDB API response:', data)

    if (!response.ok || (data.success !== undefined && !data.success)) {
        console.error('ContentDB deployment failed:', data)
        process.exit(1)
    }

    console.log(`Successfully deployed ${title} to ContentDB!`)
} catch (error) {
    console.error('Deployment error:', error)
    process.exit(1)
}
