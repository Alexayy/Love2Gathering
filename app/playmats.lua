local Playmats={}
function Playmats.install(Model)
    function Model:botPlaymatArt(player)
        local card=player and player.playmatCard;if not card or player.human then return end
        if not card.preferFullArt then return self:getArt(card,true,'art_crop')end
        local game=self.game and self.game.gameId or self.replay and self.replay.id or''
        if self.botPlaymatGame~=game then self.botPlaymatGame=game;self.botPlaymats={}end
        self.botPlaymats=self.botPlaymats or{}
        local key=tostring(player.id)..':'..tostring(card.name);local entry=self.botPlaymats[key]
        if entry and entry.reference then
            local art=self:profileArt(entry.reference);if art then return art end
        end
        local now=love.timer.getTime()
        if not entry then entry={};self.botPlaymats[key]=entry end
        if not entry.pending and(now>=(entry.retryAt or 0))then
            entry.pending=true;entry.retryAt=now+30
            self:request('catalog','GET','/playmat-art?name='..self.api.escape(card.name or'')..'&seed='..self.api.escape(tostring(player.id or'')),nil,function(data)
                if self.botPlaymatGame~=game or self.botPlaymats[key]~=entry then return end
                entry.pending=false;if data then entry.reference=data.reference end
            end,true)
        end
    end
end
return Playmats
