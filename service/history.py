"""Read-only match summaries derived from the existing SQLite recording ledger."""
import json


class HistoryStore:
    def history(self, limit=30, offset=0):
        with self.connection() as c:
            total = c.execute('SELECT count(*) FROM replays').fetchone()[0]
            rows = c.execute('SELECT id,payload,status,created_at,finished_at FROM replays ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?', (limit, offset))
            items = []
            for row in rows:
                metadata = json.loads(row['payload'])
                details = metadata.get('metadata') or {}
                frame_row = c.execute("SELECT payload FROM replay_events WHERE replay_id=? AND type='frame' ORDER BY sequence DESC LIMIT 1", (row['id'],)).fetchone()
                frame = json.loads(frame_row[0]) if frame_row else {}
                result = metadata.get('result') if isinstance(metadata.get('result'), dict) else {}
                # A finish label alone is insufficient. Results require a native
                # terminal projection/result, and aborted/failed never become wins.
                terminal = row['status'] == 'completed' and (result.get('completed') is True or frame.get('running') is False)
                native_players = result.get('players') or frame.get('players') or []
                known_flags = any(isinstance(p.get('won'), bool) or isinstance(p.get('lost'), bool) for p in native_players)
                player_info = {p.get('id') or p.get('playerId'): p for p in details.get('players', [])}
                perspective = result.get('perspectivePlayerId') or details.get('perspectivePlayerId') or metadata.get('perspectivePlayerId')
                players = []
                for p in native_players:
                    prior = player_info.get(p.get('id'), {})
                    players.append({'id': p.get('id'), 'seatId': p.get('seatId'), 'name': p.get('name') or prior.get('name') or 'Player',
                                    'deck': prior.get('deck') or {}, 'won': p.get('won') is True if terminal else None,
                                    'lost': p.get('lost') is True if terminal else None, 'local': p.get('id') == perspective or p.get('human') is True})
                if not players:
                    players = [{'id': p.get('id') or p.get('playerId'), 'name': p.get('name', 'Player'), 'deck': p.get('deck') or {}, 'won': None, 'lost': None,
                                'local': (p.get('id') or p.get('playerId')) == perspective} for p in details.get('players', [])]
                own = next((p for p in players if p['local']), None)
                outcome = 'running' if row['status'] == 'recording' else 'aborted' if row['status'] == 'aborted' else 'failed' if row['status'] == 'failed' else 'unknown'
                if terminal:
                    if own and own['won']: outcome = 'win'
                    elif own and own['lost']: outcome = 'loss'
                    elif result.get('outcome') in ('win', 'loss', 'draw'): outcome = result['outcome']
                    elif known_flags and players and not any(p['won'] for p in players): outcome = 'draw'
                legacy_deck = metadata.get('deck') if isinstance(metadata.get('deck'), dict) else {}
                items.append({'id': row['id'], 'name': metadata.get('name') or metadata.get('title') or 'Match',
                              'format': metadata.get('format') or details.get('format') or frame.get('format') or '',
                              'status': row['status'], 'outcome': outcome, 'completed': terminal,
                              'createdAt': row['created_at'], 'finishedAt': row['finished_at'], 'players': players,
                              'deck': (own or {}).get('deck') or {'name': legacy_deck.get('name', '')}})
        return {'matches': items, 'total': total, 'limit': limit, 'offset': offset}
