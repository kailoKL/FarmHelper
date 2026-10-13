local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local Marketplace = game:GetService("MarketplaceService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Se já tiver uma cópia rodando, encerra antes de iniciar esta
local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env.FarmHelperEncerrar) == "function" then pcall(env.FarmHelperEncerrar) end

-- CONFIGURAÇÕES
local INTERVAL = 240              -- anti-AFK (segundos)
local EVENT_DURATION = 180        -- duração do evento (3 min)
local CHEGOU_DIST = 5             -- distância para considerar "cheguei"
local TELEPORT_DIST = 80          -- salto de posição que conta como teleporte
local ARMA_SEG = 120              -- timer precisa estar <= isso antes do teleporte
local CLICK_DELAY = 0.2           -- intervalo entre rodadas de cliques
local MAX_CLIQUES_POR_VEZ = 3     -- quantas bolhas clicar por rodada
local MODO_CLIQUE = "auto"        -- "auto" (mouse e, se falhar, sinal), "mouse" ou "signal"
local TENTATIVAS_MOUSE = 4        -- no modo auto: tentativas de mouse antes de alternar com sinal
local CLICAR_BOLHAS = true        -- clica nas bolhas da esteira
local GUI_BOLHAS = "TreadmillBubbles" -- nome do ScreenGui das bolhas
local AUTO_REEQUIPAR = true       -- reequipa a esteira se ficar sem bolhas por um tempo
local SEM_BOLHA_SEG = 60          -- segundos sem bolhas para tentar reequipar
local CLICAR_SEM_BOTAO = false    -- false = só clica em alvo que tem botão próprio (GuiButton)
                                  -- true  = também tenta clicar em pop-up sem botão (por posição)

-- CLIQUE POR RÓTULO (botão que tem um texto por perto, ex.: "Chapéu" embaixo)
local ROTULOS_CLICAR = { "chap" } -- trechos de texto (minúsculo). Deixe {} para desligar
local ROTULO_COOLDOWN = 3         -- segundos entre cliques no mesmo botão
local ROTULO_DIST = 150           -- distância máxima (px) entre o texto e o botão

-- Nunca clicar em botões cujo nome (ou o nome do pai) tenha isto
local EVITAR_NOMES = { "config", "setting", "option", "ajust", "close", "fechar",
    "exit", "sair", "robux", "premium", "gamepass", "buy" }

-- COMPRAS: quando abrir uma janela de compra com Robux, clica no X para fechar
local BLOQUEAR_COMPRAS = true     -- detecta janelas de compra e pausa os cliques enquanto abertas
local FECHAR_COMPRAS = true       -- tenta fechar a janela (X / Cancelar)
local GUIS_COMPRA = { "CaughtSpeedOffer" } -- ScreenGuis de oferta/loja que devem ser fechados
local FECHAR_GENERICO = true      -- também fecha qualquer painel com preço em Robux e X por perto
local FECHAR_HEURISTICA = true    -- se o X não tiver nome, usa o botão pequeno do canto superior direito
local NOMES_FECHAR = { "close", "fechar", "exit", "cancel", "cancelar", "fermer", "croix", "quit", "cross" }
local TOKENS_FECHAR = { "x", "\u{D7}", "\u{2715}", "\u{2716}", "\u{2717}",
    "close", "fechar", "cancel", "cancelar", "fermer" }
local PALAVRAS_ROBUX = { "robux", "r$", "\u{E002}" }
local PALAVRAS_BOTAO_COMPRA = { "compr", "buy", "robux", "r$", "\u{E002}", "pagar",
    "purchase", "confirm", "assin", "subscri" }
-- Textos do BOTÃO que identificam o AVISO de compra do Roblox ("Comprar").
-- Lista estreita de propósito: NÃO inclui "robux", senão o botão de saldo de Robux
-- da barra superior do Roblox seria confundido com um botão de comprar.
local PALAVRAS_BOTAO_AVISO = { "comprar", "compr", "buy", "purchase", "pagar",
    "assinar", "subscrever", "subscribe" }

-- SEGURANÇA
local TECLA_PAUSA = Enum.KeyCode.F7      -- pausa/retoma TODOS os cliques
local TECLA_ENCERRAR = Enum.KeyCode.F8   -- encerra o script de vez

-- RECONEXÃO
local AUTO_RECONECTAR = true
local TENTATIVA_INTERVALO = 20           -- segundos entre tentativas
local MAX_TENTATIVAS = 40
local RECONECTAR_APOS_KICK = false       -- false = não reconecta se o jogo te expulsar
local ARQUIVO_CONFIG = "FarmHelper_config.json"
local ARQUIVO_SCRIPT = "FarmHelper.lua"  -- salve ESTE script com esse nome na pasta workspace do executor
local USAR_QUEUE_ON_TELEPORT = true      -- false se você usa a pasta autoexec do executor

-- ESTADO
local active = true
local encerrado = false
local clicks, eggRuns, cliquesEsteira = 0, 0, 0
local nextClick = os.clock() + INTERVAL
local moneyPos, toolName = nil, nil
local rodando = false
local rodandoDesde = 0
local msg = "Grave o ponto do dinheiro"

local estado = "esperando"        -- "esperando" | "evento"
local eventoInicio, eventoFim = 0, 0
local lastSecs, lastSecsAt = nil, 0

local timerList, timerIdx, timerLabel = {}, 0, nil

local alvosBolha = {}             -- bolhas achadas no TreadmillBubbles
local alvosRotulo = {}            -- botões achados por rótulo (ex.: "Chapéu")
local ultimoRotulo = {}           -- botão -> último clique
local tentativasAlvo = setmetatable({}, { __mode = "k" }) -- botão -> quantas vezes tentamos
local nVisiveis, nRotulo, nPuladas, nSemBotao = 0, 0, 0, 0
local ultimoPulo = nil            -- motivo da última bolha pulada
local rodizio = 0

local ultimaBolha = os.clock()
local ultimoClique = os.clock()
local ultimoReequipe = 0
local focado = true
local ultimoErro, erroEm = nil, 0

local bloqueio = nil              -- motivo do bloqueio global (nil = livre)
local compraAtual = nil           -- janela de compra detectada agora
local tentativasFechar, ultimoFechar = 0, 0

local config = { rejoin = false, rejoinAt = 0 }
local reconectando, tentativas, jaAgendou = false, 0, false
local capsStr, tCaps = "", -10

-- GUI (criada antes para os scanners ignorarem ela)
local gui = Instance.new("ScreenGui")
gui.Name = "FarmHelper"
gui.ResetOnSpawn = false
local okGui = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not okGui or not gui.Parent then gui.Parent = playerGui end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 270, 0, 386)
frame.Position = UDim2.new(0, 20, 0, 60)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

UserInputService.WindowFocused:Connect(function() focado = true end)
UserInputService.WindowFocusReleased:Connect(function() focado = false end)

-- Roda um bloco isolado: se der erro, registra e segue
local function seguro(nome, f)
    local ok, err = pcall(f)
    if not ok then
        local texto = nome .. ": " .. tostring(err)
        if texto ~= ultimoErro then warn("[FarmHelper] " .. texto) end
        ultimoErro = texto
        erroEm = os.clock()
    end
end

-- Utilidades
local function getChar()
    local c = player.Character
    return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local function pressKey(key)
    pcall(function()
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, key, false, game)
    end)
end

local function doClick()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
    if not bloqueio then
        pcall(function()
            local pos = workspace.CurrentCamera.ViewportSize / 2
            VIM:SendMouseButtonEvent(pos.X, pos.Y, 1, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(pos.X, pos.Y, 1, false, game, 0)
        end)
    end
    clicks += 1
end

-- Lê "3:10h" (3h10min), "03:10:25" (h:m:s), "02:58" (min:seg), "3h 10m", "2m 30s"
local function parseTime(text)
    if type(text) ~= "string" then return nil end
    local t = text:gsub("<[^>]*>", ""):lower()
    local h, m, s = t:match("(%d+)%s*:%s*(%d+)%s*:%s*(%d+)")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end
    h, m = t:match("(%d+)%s*:%s*(%d+)%s*h")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 end
    m, s = t:match("(%d+)%s*:%s*(%d+)")
    if m then return tonumber(m) * 60 + tonumber(s) end
    h, m = t:match("(%d+)%s*h%s*(%d+)%s*m")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 end
    m, s = t:match("(%d+)%s*m%s*(%d+)%s*s")
    if m then return tonumber(m) * 60 + tonumber(s) end
    return nil
end

local function isShown(obj)
    local cur = obj
    while cur and cur ~= playerGui do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return cur == playerGui and obj.AbsoluteSize.X > 0
end

local function fmt(s)
    s = math.max(0, math.floor(s))
    return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end

local function isTextObj(o)
    return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
end

-- Visível "de verdade": numa ScreenGui, mostrado, dentro da tela e sem transparência total
local function visivelDeVerdade(o)
    if not o:FindFirstAncestorWhichIsA("ScreenGui") then return false end
    if not isShown(o) then return false end
    local vp = workspace.CurrentCamera.ViewportSize
    local c = o.AbsolutePosition + o.AbsoluteSize / 2
    if c.X < 0 or c.Y < 0 or c.X > vp.X or c.Y > vp.Y then return false end
    if isTextObj(o) and o.TextTransparency > 0.95 then return false end
    local cur = o
    while cur and cur ~= playerGui do
        if cur:IsA("CanvasGroup") and cur.GroupTransparency > 0.95 then return false end
        cur = cur.Parent
    end
    return true
end

-- Algo que realmente desenha na tela (não é só um contêiner transparente)
local function pintado(o)
    if o:IsA("TextLabel") or o:IsA("TextButton") then
        return o.Text ~= "" and o.TextTransparency < 0.9
    end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then
        return o.Image ~= "" and o.ImageTransparency < 0.9
    end
    if o:IsA("GuiObject") then
        return o.BackgroundTransparency < 0.9
    end
    return false
end

-- Visibilidade para objetos do CoreGui (avisos do Roblox)
local function visivelCore(o)
    local cur = o
    while cur do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") then
            if not cur.Enabled then return false end
            break
        end
        cur = cur.Parent
    end
    return o:IsA("GuiObject") and o.AbsoluteSize.X > 0
end

-- Texto de ganho: "+85M", "+85.5M", "+850K"
local function ehValorGanho(text)
    if type(text) ~= "string" then return false end
    local t = text:gsub("<[^>]*>", "")
    return t:match("^%s*%+%s*[%d%.,]+%s*[KkMmBbTtQq]") ~= nil
end

local function acharBotaoDoValor(o)
    local cur = o
    while cur and cur ~= playerGui do
        if cur:IsA("GuiButton") then return cur end
        cur = cur.Parent
    end
    return nil
end

local function cadeia(o)
    local partes, cur = {}, o
    while cur and cur ~= playerGui and #partes < 6 do
        table.insert(partes, cur.ClassName .. ":" .. cur.Name)
        cur = cur.Parent
    end
    return table.concat(partes, " < ")
end

local function nomeProibido(b)
    local t = (b.Name .. " " .. (b.Parent and b.Parent.Name or "")):lower()
    for _, p in ipairs(EVITAR_NOMES) do
        if t:find(p, 1, true) then return true end
    end
    return false
end

local function textoCombina(t, lista)
    t = t:lower()
    for _, p in ipairs(lista) do
        if t:find(p, 1, true) then return true end
    end
    return false
end

-- ARQUIVOS (salvar ponto do dinheiro, esteira e flag de reconexão)
local function podeArquivo()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

local function salvarConfig()
    if not podeArquivo() then return false end
    local dados = {
        money = moneyPos and { x = moneyPos.X, y = moneyPos.Y, z = moneyPos.Z } or nil,
        tool = toolName,
        rejoin = config.rejoin,
        rejoinAt = config.rejoinAt,
    }
    local ok = pcall(function() writefile(ARQUIVO_CONFIG, HttpService:JSONEncode(dados)) end)
    return ok
end

local function carregarConfig()
    if not podeArquivo() then return end
    pcall(function()
        if isfile(ARQUIVO_CONFIG) then
            local d = HttpService:JSONDecode(readfile(ARQUIVO_CONFIG))
            if d.money then moneyPos = Vector3.new(d.money.x, d.money.y, d.money.z) end
            if d.tool then toolName = d.tool end
            config.rejoin = (d.rejoin == true)
            config.rejoinAt = d.rejoinAt or 0
        end
    end)
end
carregarConfig()

-- RECONEXÃO (utilidades)
local function acharQOT()
    return queue_on_teleport or queueonteleport
        or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
end

local function capsTexto()
    if not AUTO_RECONECTAR then return "desligada" end
    if not podeArquivo() then return "SEM writefile (não salva posição)" end
    if USAR_QUEUE_ON_TELEPORT then
        if not acharQOT() then return "SEM queue_on_teleport (use autoexec)" end
        local okF, existe = pcall(isfile, ARQUIVO_SCRIPT)
        if not (okF and existe) then return "salve este script como " .. ARQUIVO_SCRIPT end
    end
    return "pronta"
end

local function agendarReexecucao()
    if jaAgendou or not USAR_QUEUE_ON_TELEPORT then return end
    local qot = acharQOT()
    if qot and type(isfile) == "function" then
        local okF, existe = pcall(isfile, ARQUIVO_SCRIPT)
        if okF and existe then
            local ok = pcall(qot, 'loadstring(readfile("' .. ARQUIVO_SCRIPT .. '"))()')
            if ok then jaAgendou = true end
        end
    end
end

local function reconectarPermitido(texto)
    local t = (texto or ""):lower()
    if t:find("%f[%a]ban") or t:find("moderat") or t:find("suspen") or t:find("terminat") then
        return false, "possível punição da conta"
    end
    if not RECONECTAR_APOS_KICK and (t:find("kicked") or t:find("code: 267") or t:find("expuls")) then
        if not (t:find("idle") or t:find("inativ") or t:find("ocios") or t:find("278")) then
            return false, "expulso pelo jogo"
        end
    end
    return true, nil
end

local function iniciarReconexao(texto)
    if not AUTO_RECONECTAR or reconectando or encerrado then return end
    local permitido, porque = reconectarPermitido(texto)
    if not permitido then
        msg = "Desconectado (" .. porque .. "): NÃO vou reconectar"
        return
    end
    reconectando = true
    task.spawn(function()
        config.rejoin = true
        config.rejoinAt = os.time()
        salvarConfig()
        agendarReexecucao()
        while tentativas < MAX_TENTATIVAS and not encerrado do
            tentativas += 1
            msg = string.format("Desconectado: reconectando (%d/%d)", tentativas, MAX_TENTATIVAS)
            pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
            task.wait(TENTATIVA_INTERVALO)
        end
        if not encerrado then
            msg = "Não consegui reconectar (" .. MAX_TENTATIVAS .. " tentativas)"
        end
        reconectando = false
    end)
end

local function mensagemErro()
    local m = ""
    pcall(function() m = GuiService:GetErrorMessage() end)
    return m or ""
end

local function ligarDeteccaoDesconexao()
    pcall(function()
        GuiService.ErrorMessageChanged:Connect(function()
            local m = mensagemErro()
            if m ~= "" then iniciarReconexao(m) end
        end)
    end)
    pcall(function()
        local cg = game:GetService("CoreGui")
        local prompt = cg:WaitForChild("RobloxPromptGui", 10)
        local overlay = prompt and prompt:WaitForChild("promptOverlay", 10)
        if overlay then
            overlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    task.wait(0.5)
                    local texto = ""
                    pcall(function() texto = child.MessageArea.ErrorFrame.ErrorMessage.Text end)
                    if texto == "" then texto = mensagemErro() end
                    iniciarReconexao(texto)
                end
            end)
        end
    end)
end

-- COMPRAS: detectar janela de compra e achar o botão de fechar
local function textosDoBotao(b)
    local lista = {}
    if isTextObj(b) and b.Text ~= "" then table.insert(lista, b.Text) end
    for _, d in ipairs(b:GetDescendants()) do
        if isTextObj(d) and d.Text ~= "" then table.insert(lista, d.Text) end
    end
    return lista
end

local function textoEhFechar(t, permitirOk)
    t = t:gsub("<[^>]*>", "")
    t = t:gsub("%s+", "")
    t = t:lower()
    if t == "" then return false end
    for _, p in ipairs(TOKENS_FECHAR) do
        if t == p then return true end
    end
    return permitirOk == true and t == "ok"
end

-- É um botão de fechar/cancelar? (nunca um botão de comprar)
local function ehBotaoFechar(b, permitirOk)
    if not b:IsA("GuiButton") then return false end
    local textos = textosDoBotao(b)
    for _, t in ipairs(textos) do
        if textoCombina(t, PALAVRAS_BOTAO_COMPRA) then return false end
    end
    local nome = b.Name:lower()
    local pai = b.Parent and b.Parent.Name:lower() or ""
    if nome == "x" or pai == "x" then return true end
    for _, p in ipairs(NOMES_FECHAR) do
        if nome:find(p, 1, true) or pai:find(p, 1, true) then return true end
    end
    for _, t in ipairs(textos) do
        if textoEhFechar(t, permitirOk) then return true end
    end
    return false
end

-- Procura o X dentro de uma raiz (perto de uma âncora, se ela for dada)
local function acharFechar(root, ancora, maxDist)
    local melhor, melhorD = nil, nil
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and not d:IsDescendantOf(gui)
            and visivelDeVerdade(d) and ehBotaoFechar(d, false) then
            if not ancora then return d end
            local dist = ((d.AbsolutePosition + d.AbsoluteSize / 2) - ancora).Magnitude
            if dist <= (maxDist or math.huge) and (not melhorD or dist < melhorD) then
                melhor, melhorD = d, dist
            end
        end
    end
    return melhor
end

-- X sem nome: botão pequeno mais perto do canto superior direito do painel principal
local function acharFecharHeuristico(root)
    local vp = workspace.CurrentCamera.ViewportSize
    local painel, maiorArea = nil, 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiObject") and not d:IsA("GuiButton") and visivelDeVerdade(d) and pintado(d) then
            local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
            if a > maiorArea and a < vp.X * vp.Y * 0.9 then painel, maiorArea = d, a end
        end
    end
    if not painel then return nil end
    local canto = painel.AbsolutePosition + Vector2.new(painel.AbsoluteSize.X, 0)
    local melhor, melhorD = nil, 110
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and visivelDeVerdade(d)
            and d.AbsoluteSize.X <= 90 and d.AbsoluteSize.Y <= 90 then
            local ok = true
            for _, t in ipairs(textosDoBotao(d)) do
                if textoCombina(t, PALAVRAS_BOTAO_COMPRA) then ok = false end
            end
            if ok then
                local dist = ((d.AbsolutePosition + d.AbsoluteSize / 2) - canto).Magnitude
                if dist < melhorD then melhor, melhorD = d, dist end
            end
        end
    end
    return melhor
end

-- Algum elemento desenhado e visível dentro da raiz?
local function conteudoVisivel(root)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiObject") and d.AbsoluteSize.X >= 40 and d.AbsoluteSize.Y >= 40
            and visivelDeVerdade(d) and pintado(d) then
            return true
        end
    end
    return false
end

-- X de um aviso do Roblox (CoreGui): primeiro por nome/texto (Close, Exit, X,
-- Cancelar...); se não achar, o botão pequeno perto do canto superior direito do
-- aviso. Nunca devolve um botão de comprar.
local function acharFecharCore(root)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and not d:IsDescendantOf(gui) and visivelCore(d)
            and ehBotaoFechar(d, false) then
            return d
        end
    end
    local vp = workspace.CurrentCamera.ViewportSize
    local painel, maiorArea = nil, 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiObject") and not d:IsA("GuiButton") and visivelCore(d) and pintado(d) then
            local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
            -- ignora fundo de tela cheia: o aviso é uma caixa pequena e flutuante
            if a > maiorArea and a < vp.X * vp.Y * 0.6 then painel, maiorArea = d, a end
        end
    end
    local canto = painel and (painel.AbsolutePosition + Vector2.new(painel.AbsoluteSize.X, 0))
        or Vector2.new(vp.X, 0)
    local melhor, melhorD = nil, 140
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and visivelCore(d)
            and d.AbsoluteSize.X >= 12 and d.AbsoluteSize.X <= 80
            and d.AbsoluteSize.Y >= 12 and d.AbsoluteSize.Y <= 80 then
            local pode = true
            for _, t in ipairs(textosDoBotao(d)) do
                if textoCombina(t, PALAVRAS_BOTAO_COMPRA) then pode = false end
            end
            if pode then
                local dist = ((d.AbsolutePosition + d.AbsoluteSize / 2) - canto).Magnitude
                if dist < melhorD then melhor, melhorD = d, dist end
            end
        end
    end
    return melhor
end

-- Aviso de compra do Roblox (CoreGui), ex.: "Comprar Robux e item".
-- Detecta pelo BOTÃO de comprar dentro de uma ScreenGui do CoreGui: é assim que os
-- avisos do Roblox são montados hoje, e o nome da ScreenGui muda a cada atualização
-- (por isso a busca não depende mais de o nome conter "purchase").
-- Devolve o X (ou o Cancelar) para fechar.
local function compraNativa()
    local ok, res = pcall(function()
        local cg = game:GetService("CoreGui")
        for _, g in ipairs(cg:GetChildren()) do
            if g ~= gui and g:IsA("ScreenGui") and g.Enabled then
                local botaoComprar, titulo = nil, nil
                for _, o in ipairs(g:GetDescendants()) do
                    if o:IsA("GuiButton") and visivelCore(o) then
                        for _, t in ipairs(textosDoBotao(o)) do
                            if textoCombina(t, PALAVRAS_BOTAO_AVISO) then botaoComprar = o; break end
                        end
                    end
                    if not titulo and isTextObj(o) and o.Text ~= "" and visivelCore(o) then
                        local tl = o.Text:lower()
                        if tl:find("comprar", 1, true) or tl:find("compr", 1, true)
                            or tl:find("buy", 1, true) or tl:find("purchase", 1, true) then
                            titulo = (o.Text:gsub("\n", " "))
                        end
                    end
                end
                if botaoComprar then
                    return { cancelar = acharFecharCore(g), nome = titulo or g.Name, gui = g }
                end
            end
        end
        return nil
    end)
    if ok then return res end
    return nil
end

-- Painel qualquer com preço em Robux e um X por perto
local function acharCompraGenerica()
    local vp = workspace.CurrentCamera.ViewportSize
    for _, o in ipairs(playerGui:GetDescendants()) do
        if isTextObj(o) and not o:IsDescendantOf(gui) and o.Text ~= ""
            and textoCombina(o.Text, PALAVRAS_ROBUX) and visivelDeVerdade(o) then
            local oc = o.AbsolutePosition + o.AbsoluteSize / 2
            local cur, nivel = o.Parent, 0
            while cur and cur:IsA("GuiObject") and nivel < 6 do
                if cur.AbsoluteSize.X > vp.X * 0.75 or cur.AbsoluteSize.Y > vp.Y * 0.75 then break end
                local btn = acharFechar(cur, oc, 450)
                if btn then
                    return { motivo = "painel de compra aberto (" .. o.Name .. ")", fechar = btn, core = false }
                end
                cur = cur.Parent
                nivel += 1
            end
        end
    end
    return nil
end

-- Resultado: nil (nada aberto) ou { motivo, fechar = botão|nil, core = bool }
local function acharJanelaCompra()
    if not BLOQUEAR_COMPRAS then return nil end

    local nativa = compraNativa()
    if nativa then
        return { motivo = "aviso de compra do Roblox aberto", fechar = nativa.cancelar, core = true }
    end

    for _, nome in ipairs(GUIS_COMPRA) do
        local g = playerGui:FindFirstChild(nome)
        if g and g:IsA("ScreenGui") and g.Enabled and conteudoVisivel(g) then
            local btn = acharFechar(g, nil, nil)
            if not btn and FECHAR_HEURISTICA then btn = acharFecharHeuristico(g) end
            return { motivo = "oferta aberta: " .. nome, fechar = btn, core = false }
        end
    end

    if FECHAR_GENERICO then
        local r = acharCompraGenerica()
        if r then return r end
    end
    return nil
end

-- Só pausa se a compra realmente aconteceu (cancelar não pausa)
local function pausaPorCompra(nome)
    active = false
    msg = "COMPRA realizada (" .. nome .. "): pausado"
end
pcall(function() Marketplace.PromptProductPurchaseFinished:Connect(function(_, _, comprou)
    if comprou then pausaPorCompra("produto") end end) end)
pcall(function() Marketplace.PromptGamePassPurchaseFinished:Connect(function(_, _, comprou)
    if comprou then pausaPorCompra("gamepass") end end) end)
pcall(function() Marketplace.PromptPurchaseFinished:Connect(function(_, _, comprou)
    if comprou then pausaPorCompra("item") end end) end)
pcall(function() Marketplace.PromptBundlePurchaseFinished:Connect(function(_, _, comprou)
    if comprou then pausaPorCompra("pacote") end end) end)

-- CLIQUES: posição, sinal direto e avaliação de alvos
-- modo: "full" (centro + barra superior), "half" (meio-termo, acerta com ou sem ajuste), "zero" (sem ajuste)
local function centroTela(btn, modo)
    local c = btn.AbsolutePosition + btn.AbsoluteSize / 2
    local sg = btn:FindFirstAncestorWhichIsA("ScreenGui")
    if sg and not sg.IgnoreGuiInset then
        local ins = GuiService:GetGuiInset()
        if modo == "zero" then
            -- sem ajuste
        elseif modo == "half" then
            c = c + ins / 2
        else
            c = c + ins
        end
    end
    return c
end

local function podeSinal(b)
    return b:IsA("GuiButton") and (type(firesignal) == "function" or type(getconnections) == "function")
end

-- Aciona o botão direto (não depende de posição nem clica em outras coisas)
local function dispararBotao(btn)
    local sinais = { btn.Activated, btn.MouseButton1Click }
    if type(firesignal) == "function" then
        for _, s in ipairs(sinais) do
            pcall(firesignal, s)
        end
    elseif type(getconnections) == "function" then
        for _, s in ipairs(sinais) do
            pcall(function()
                for _, c in ipairs(getconnections(s)) do
                    local ok = pcall(function() c:Fire() end)
                    if not ok then pcall(c.Function) end
                end
            end)
        end
    end
end

-- Outro botão (de outra ScreenGui) visível no ponto do clique, se houver
local function temOutroBotaoAli(b)
    local c = b.AbsolutePosition + b.AbsoluteSize / 2
    local ok, lista = pcall(function() return playerGui:GetGuiObjectsAtPosition(c.X, c.Y) end)
    if not ok or type(lista) ~= "table" then return nil end
    local sgB = b:FindFirstAncestorWhichIsA("ScreenGui")
    local ordemB = sgB and sgB.DisplayOrder or 0
    local ignorarMesma = sgB ~= nil and sgB.Name == GUI_BOLHAS
    for _, o in ipairs(lista) do
        if o:IsA("GuiButton") and o ~= b
            and not o:IsDescendantOf(gui)
            and not o:IsDescendantOf(b) and not b:IsDescendantOf(o)
            and not (ignorarMesma and o:IsDescendantOf(sgB))
            and isShown(o) then
            local sgO = o:FindFirstAncestorWhichIsA("ScreenGui")
            if sgO and sgO.DisplayOrder >= ordemB then return o end
        end
    end
    return nil
end

-- Avalia um alvo: devolve "mouse", "sinal" ou nil + motivo
local function avaliarAlvo(b)
    if not (b.Parent and isShown(b)) then return nil, "não visível" end
    -- Nunca clicar em algo que não tenha botão próprio
    if not CLICAR_SEM_BOTAO and not b:IsA("GuiButton") then
        return nil, "sem botão próprio"
    end
    if b.AbsoluteSize.X < 20 or b.AbsoluteSize.Y < 20 then return nil, "pequeno demais" end
    local c = centroTela(b, "full")
    local vp = workspace.CurrentCamera.ViewportSize
    if c.X < 0 or c.Y < 0 or c.X > vp.X or c.Y > vp.Y then return nil, "fora da tela" end

    local sobreposto = nil
    local inset = gui.IgnoreGuiInset and Vector2.new(0, 0) or GuiService:GetGuiInset()
    local fp = frame.AbsolutePosition + inset
    local fs = frame.AbsoluteSize
    if c.X >= fp.X and c.X <= fp.X + fs.X and c.Y >= fp.Y and c.Y <= fp.Y + fs.Y then
        sobreposto = "janela do script por cima"
    else
        local outro = temOutroBotaoAli(b)
        if outro then sobreposto = "botão por cima: " .. outro.Name end
    end

    if sobreposto then
        if MODO_CLIQUE ~= "mouse" and podeSinal(b) then return "sinal", sobreposto end
        return nil, sobreposto .. " (sem firesignal)"
    end
    return "mouse", nil
end

-- Escolhe a forma do clique: mouse, sinal, ou alternando depois de várias tentativas
local function formaDoClique(b, base)
    local n = tentativasAlvo[b] or 0
    tentativasAlvo[b] = n + 1
    if MODO_CLIQUE == "signal" and podeSinal(b) then return "sinal" end
    if base == "sinal" then return "sinal" end
    if MODO_CLIQUE == "auto" and n >= TENTATIVAS_MOUSE and podeSinal(b) then
        return (n % 2 == 0) and "sinal" or "mouse"
    end
    return "mouse"
end

-- Timer do evento: aceita qualquer texto com formato de hora, melhores primeiro
local function score(o)
    local t = (o.Text .. o.Name .. (o.Parent and o.Parent.Name or "")):lower()
    if t:find("ovo", 1, true) or t:find("egg", 1, true) or o.Text:find("\u{1F95A}", 1, true) then
        return 1
    end
    return 0
end

local function acharTimers()
    local vp = workspace.CurrentCamera.ViewportSize
    local itens = {}
    for _, o in ipairs(playerGui:GetDescendants()) do
        if isTextObj(o) and not o:IsDescendantOf(gui) and parseTime(o.Text) then
            local p = o.AbsolutePosition
            local pts = 0
            if score(o) > 0 then pts += 100 end
            if isShown(o) then pts += 20 end
            if p.X < vp.X * 0.4 and p.Y > vp.Y * 0.55 then pts += 10 end
            table.insert(itens, { obj = o, pts = pts, nome = o:GetFullName() })
        end
    end
    table.sort(itens, function(a, b)
        if a.pts ~= b.pts then return a.pts > b.pts end
        return a.nome < b.nome
    end)
    local lista = {}
    for _, it in ipairs(itens) do table.insert(lista, it.obj) end
    return lista
end

-- Diagnóstico
local function diagnostico()
    local vp = workspace.CurrentCamera.ViewportSize
    local agora = os.clock()
    local linhas = {}

    local char2 = player.Character
    table.insert(linhas, string.format(
        "ESTADO: estado=%s rodando=%s ativo=%s foco=%s alvosBolha=%d visiveis=%d puladas=%d rotulo=%d semBotao=%d",
        estado, tostring(rodando), tostring(active), tostring(focado),
        #alvosBolha, nVisiveis, nPuladas, nRotulo, nSemBotao))
    table.insert(linhas, string.format("BLOQUEIO: %s | ultimoPulo=%s | tentativasFechar=%d",
        tostring(bloqueio), tostring(ultimoPulo), tentativasFechar))
    table.insert(linhas, string.format("CLIQUE: modo=%s | firesignal=%s | getconnections=%s | inset=%s",
        MODO_CLIQUE, tostring(type(firesignal) == "function"),
        tostring(type(getconnections) == "function"), tostring(GuiService:GetGuiInset())))
    table.insert(linhas, string.format("CLIQUES LIGADOS: pausado=%s | clicaSemBotao=%s",
        tostring(not active), tostring(CLICAR_SEM_BOTAO)))
    table.insert(linhas, string.format("RECONEXAO: %s | reconectando=%s tentativas=%d",
        capsTexto(), tostring(reconectando), tentativas))
    table.insert(linhas, string.format(
        "esteira=%s equipada=%s ultimaBolha=ha %ds ultimoClique=ha %ds",
        tostring(toolName),
        tostring(char2 ~= nil and toolName ~= nil and char2:FindFirstChild(toolName) ~= nil),
        math.floor(agora - ultimaBolha), math.floor(agora - ultimoClique)))
    table.insert(linhas, "ULTIMO ERRO: " .. tostring(ultimoErro))
    table.insert(linhas, string.format("tela=%dx%d | janela do script @ %d,%d %dx%d", math.floor(vp.X),
        math.floor(vp.Y), math.floor(frame.AbsolutePosition.X), math.floor(frame.AbsolutePosition.Y),
        math.floor(frame.AbsoluteSize.X), math.floor(frame.AbsoluteSize.Y)))

    -- Avaliação de cada bolha
    table.insert(linhas, "--- BOLHAS (avaliacao) ---")
    local sgb2 = playerGui:FindFirstChild(GUI_BOLHAS)
    if sgb2 then
        local nbol = 0
        for _, topo in ipairs(sgb2:GetChildren()) do
            if topo:IsA("GuiObject") then
                nbol += 1
                local btn = topo:IsA("GuiButton") and topo or topo:FindFirstChildWhichIsA("GuiButton", true)
                local modo, why = nil, "sem botao"
                local cx, cy, tent = 0, 0, 0
                if btn then
                    modo, why = avaliarAlvo(btn)
                    local c = centroTela(btn, "full")
                    cx, cy = math.floor(c.X), math.floor(c.Y)
                    tent = tentativasAlvo[btn] or 0
                end
                table.insert(linhas, string.format("%s | %s | centro=%d,%d | resultado=%s | motivo=%s | tentativas=%d",
                    topo.Name, topo.Visible and "vis" or "oculto", cx, cy,
                    tostring(modo), tostring(why), tent))
            end
        end
        if nbol == 0 then table.insert(linhas, "(nenhuma bolha agora)") end
    else
        table.insert(linhas, "ScreenGui das bolhas nao existe agora")
    end

    -- Janela de compra
    table.insert(linhas, "--- COMPRA ---")
    local okC, comp = pcall(acharJanelaCompra)
    if okC and comp then
        table.insert(linhas, string.format("janela de compra: %s | fechar=%s | core=%s",
            comp.motivo, comp.fechar and comp.fechar:GetFullName() or "NAO ACHEI", tostring(comp.core)))
    elseif okC then
        table.insert(linhas, "nenhuma janela de compra detectada agora")
    else
        table.insert(linhas, "erro ao detectar compra: " .. tostring(comp))
    end
    for _, nome in ipairs(GUIS_COMPRA) do
        local g = playerGui:FindFirstChild(nome)
        if g then
            local cv = g:IsA("ScreenGui") and conteudoVisivel(g)
            table.insert(linhas, string.format("GUI %s | enabled=%s | conteudoVisivel=%s",
                nome, tostring(g:IsA("ScreenGui") and g.Enabled), tostring(cv)))
            local k = 0
            for _, o in ipairs(g:GetDescendants()) do
                k += 1
                if k > 60 then break end
                local depth, cur = 0, o
                while cur.Parent and cur.Parent ~= g do depth += 1; cur = cur.Parent end
                local info = string.rep("  ", depth) .. o.ClassName .. ":" .. o.Name
                if o:IsA("GuiObject") then
                    info = info .. string.format(" | %s | %dx%d @ %d,%d",
                        o.Visible and "vis" or "oculto",
                        math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
                        math.floor(o.AbsolutePosition.X), math.floor(o.AbsolutePosition.Y))
                end
                if isTextObj(o) and o.Text ~= "" then info = info .. " | '" .. o.Text .. "'" end
                table.insert(linhas, info)
            end
        else
            table.insert(linhas, "GUI " .. nome .. " nao existe agora")
        end
    end

    -- CoreGui: onde vive o aviso "Comprar Robux e item" do próprio Roblox
    table.insert(linhas, "--- COREGUI (avisos do Roblox) ---")
    local okCG = pcall(function()
        local cg = game:GetService("CoreGui")
        for _, g in ipairs(cg:GetChildren()) do
            if g:IsA("ScreenGui") and g.Enabled then
                local nbtn, ntxt, nc = 0, 0, 0
                for _, o in ipairs(g:GetDescendants()) do
                    if o:IsA("GuiButton") and visivelCore(o) then
                        nbtn += 1
                        for _, t in ipairs(textosDoBotao(o)) do
                            if textoCombina(t, PALAVRAS_BOTAO_AVISO) then nc += 1; break end
                        end
                    end
                    if isTextObj(o) and o.Text ~= "" and visivelCore(o) then ntxt += 1 end
                end
                table.insert(linhas, string.format("%s | botoes=%d textos=%d botoesComprar=%d",
                    g.Name, nbtn, ntxt, nc))
            end
        end
    end)
    if not okCG then table.insert(linhas, "CoreGui nao acessivel por este executor") end

    -- Botões visíveis (com o texto de cada um)
    table.insert(linhas, "--- BOTOES VISIVEIS ---")
    local nb = 0
    for _, o in ipairs(playerGui:GetDescendants()) do
        if o:IsA("GuiButton") and not o:IsDescendantOf(gui) and isShown(o) then
            nb += 1
            if nb <= 40 then
                local rot = ""
                for _, d in ipairs(o:GetDescendants()) do
                    if isTextObj(d) and d.Text ~= "" then rot = d.Text break end
                end
                if rot == "" and isTextObj(o) then rot = o.Text end
                table.insert(linhas, string.format("%s:%s | '%s' | %dx%d @ %d,%d | %s",
                    o.ClassName, o.Name, (rot:gsub("\n", " ")),
                    math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
                    math.floor(o.AbsolutePosition.X), math.floor(o.AbsolutePosition.Y),
                    cadeia(o)))
            end
        end
    end
    table.insert(linhas, "total de botoes visiveis: " .. nb)

    -- Textos "chapéu"
    table.insert(linhas, "--- TEXTOS CHAPEU ---")
    local nc = 0
    for _, o in ipairs(playerGui:GetDescendants()) do
        if isTextObj(o) and not o:IsDescendantOf(gui) and o.Text ~= "" then
            local t = o.Text:lower()
            if (t:find("chap", 1, true) or t:find("hat", 1, true)) and isShown(o) then
                nc += 1
                if nc <= 10 then
                    local b = acharBotaoDoValor(o)
                    table.insert(linhas, string.format("'%s' | %dx%d @ %d,%d | dentroDeBotao=%s | %s",
                        (o.Text:gsub("\n", " ")),
                        math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
                        math.floor(o.AbsolutePosition.X), math.floor(o.AbsolutePosition.Y),
                        b and (b.ClassName .. ":" .. b.Name) or "NAO", cadeia(o)))
                end
            end
        end
    end
    if nc == 0 then table.insert(linhas, "nenhum texto 'chapeu' visivel agora") end

    -- Árvore das bolhas
    table.insert(linhas, "--- ARVORE " .. GUI_BOLHAS .. " ---")
    local sgb = playerGui:FindFirstChild(GUI_BOLHAS)
    if sgb then
        local k = 0
        for _, o in ipairs(sgb:GetDescendants()) do
            k += 1
            if k > 60 then break end
            local depth, cur = 0, o
            while cur.Parent and cur.Parent ~= sgb do depth += 1; cur = cur.Parent end
            local info = string.rep("  ", depth) .. o.ClassName .. ":" .. o.Name
            if o:IsA("GuiObject") then
                info = info .. string.format(" | %s | %dx%d @ %d,%d",
                    o.Visible and "vis" or "oculto",
                    math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
                    math.floor(o.AbsolutePosition.X), math.floor(o.AbsolutePosition.Y))
            end
            if isTextObj(o) then info = info .. " | '" .. o.Text .. "'" end
            table.insert(linhas, info)
        end
        if k == 0 then table.insert(linhas, "(vazio agora)") end
    else
        table.insert(linhas, "ScreenGui nao existe agora")
    end

    local texto = table.concat(linhas, "\n")
    print(texto)
    if setclipboard then
        local ok2 = pcall(setclipboard, texto)
        msg = ok2 and "Diagnóstico copiado (cole no chat)" or "Veja o console (F9)"
    else
        msg = "Sem clipboard: veja o console (F9)"
    end
end

-- Alvos: bolhas (filhas do ScreenGui das bolhas)
local function refrescarAlvosBolha()
    alvosBolha = {}
    nSemBotao = 0
    local sg = playerGui:FindFirstChild(GUI_BOLHAS)
    if not sg then return end
    for _, topo in ipairs(sg:GetChildren()) do
        if topo:IsA("GuiObject") then
            local btn = topo:IsA("GuiButton") and topo or topo:FindFirstChildWhichIsA("GuiButton", true)
            if btn then
                if not nomeProibido(btn) then table.insert(alvosBolha, btn) end
            else
                -- sem botão próprio: parece bolha? então só clica se CLICAR_SEM_BOTAO = true
                local usa = false
                for _, d in ipairs(topo:GetDescendants()) do
                    if isTextObj(d) and d.Text ~= "" then
                        local tl = d.Text:lower()
                        if ehValorGanho(d.Text) or tl:find("toque", 1, true) or tl:find("tap", 1, true) then
                            usa = true
                            break
                        end
                    end
                end
                if usa then
                    if CLICAR_SEM_BOTAO then
                        table.insert(alvosBolha, topo)
                    else
                        nSemBotao += 1 -- não clico: não tem botão próprio
                    end
                end
            end
        end
    end
end

-- Alvos: botão mais próximo de um texto como "Chapéu"
local function acharBotoesPorRotulo()
    local resultado, jaTem = {}, {}
    local vp = workspace.CurrentCamera.ViewportSize
    for _, o in ipairs(playerGui:GetDescendants()) do
        if isTextObj(o) and not o:IsDescendantOf(gui) and o.Text ~= ""
            and textoCombina(o.Text, ROTULOS_CLICAR) and isShown(o) then
            local btn = acharBotaoDoValor(o) -- o texto já está dentro de um botão?
            if not btn then
                local oc = o.AbsolutePosition + o.AbsoluteSize / 2
                local melhor, melhorD = nil, ROTULO_DIST
                local cont, nivel = o.Parent, 0
                while cont and cont:IsA("GuiObject") and nivel < 3 do
                    if cont.AbsoluteSize.X > vp.X * 0.3 or cont.AbsoluteSize.Y > vp.Y * 0.3 then break end
                    for _, d in ipairs(cont:GetDescendants()) do
                        if d:IsA("GuiButton") and isShown(d) and not nomeProibido(d) then
                            local dist = ((d.AbsolutePosition + d.AbsoluteSize / 2) - oc).Magnitude
                            if dist < melhorD then melhor, melhorD = d, dist end
                        end
                    end
                    if melhor then break end
                    cont = cont.Parent
                    nivel += 1
                end
                btn = melhor
            end
            if btn and not nomeProibido(btn) and not jaTem[btn] then
                jaTem[btn] = true
                table.insert(resultado, btn)
            end
        end
    end
    return resultado
end

-- Clica num alvo (forma: "mouse" ou "sinal")
local function clicarGui(btn, forma)
    -- última checagem antes de clicar
    if not active or bloqueio then return end
    if not btn.Parent then return end
    if forma == "sinal" and podeSinal(btn) then
        dispararBotao(btn)
    else
        local c = centroTela(btn, "half")
        pcall(function()
            VIM:SendMouseMoveEvent(c.X, c.Y, game)
            task.wait(0.02)
            VIM:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 0)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 0)
        end)
    end
    cliquesEsteira += 1
    ultimoClique = os.clock()
end

-- Fecha a janela de compra: tentativa 1 = sinal, 2 = mouse, 3 = sinal + mouse, 4 = mouse sem ajuste
local function botaoAindaVisivel(b, core)
    if not b or not b.Parent then return false end
    if core then return visivelCore(b) end
    return visivelDeVerdade(b)
end

local function fecharAgora(compra)
    local b = compra.fechar
    if not botaoAindaVisivel(b, compra.core) then return end
    tentativasFechar += 1
    local n = tentativasFechar
    msg = string.format("Fechando janela de compra (%d/4)", n)
    -- No aviso do Roblox (CoreGui) o sinal não é confiável: vai de mouse direto
    local sinal = (n == 1 or n == 3) and type(firesignal) == "function" and not compra.core
    if sinal then
        pcall(function() firesignal(b.Activated) end)
        pcall(function() firesignal(b.MouseButton1Click) end)
        task.wait(0.3)
        if not botaoAindaVisivel(b, compra.core) then return end
    end
    if n >= 2 or not sinal then
        local c = centroTela(b, (n == 4) and "zero" or "full")
        pcall(function()
            VIM:SendMouseMoveEvent(c.X, c.Y, game)
            task.wait(0.02)
            VIM:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 0)
        end)
    end
end

-- Voltar ao dinheiro e equipar esteira
local function irParaDinheiro(limite)
    limite = limite or 30
    local _, hum, root = getChar()
    if not (hum and root and moneyPos) then return false end
    local t0 = os.clock()
    while os.clock() - t0 < limite do
        if (root.Position - moneyPos).Magnitude <= CHEGOU_DIST then return true end
        hum:MoveTo(moneyPos)
        task.wait(0.5)
    end
    return (root.Position - moneyPos).Magnitude <= CHEGOU_DIST
end

local function equiparEsteira()
    local char, hum = getChar()
    if not (char and hum) then return end
    if toolName then
        if char:FindFirstChild(toolName) then return end
        local tool = player.Backpack:FindFirstChild(toolName)
        if tool then hum:EquipTool(tool) return end
    end
    if not char:FindFirstChildOfClass("Tool") then
        pressKey(Enum.KeyCode.Two)
    end
end

local function esteiraEquipada()
    local char = player.Character
    if not char then return false end
    if toolName then return char:FindFirstChild(toolName) ~= nil end
    return char:FindFirstChildOfClass("Tool") ~= nil
end

-- Tenta equipar até 6 vezes, confirmando que ficou na mão
local function garantirEsteira()
    for _ = 1, 6 do
        if esteiraEquipada() then return true end
        equiparEsteira()
        task.wait(1.5)
    end
    return esteiraEquipada()
end

local function sequenciaPosOvo(limite)
    if rodando then return end
    rodando = true
    rodandoDesde = os.clock()
    local ok, err = pcall(function()
        msg = "Voltando ao dinheiro..."
        task.wait(1)
        if irParaDinheiro(limite) then
            task.wait(0.3)
            if garantirEsteira() then
                eggRuns += 1
                msg = "OK " .. os.date("%H:%M:%S")
            else
                msg = "Cheguei, mas a esteira não equipou"
            end
        else
            msg = "NÃO CHEGOU ao dinheiro"
        end
    end)
    if not ok then msg = "Erro na sequência: " .. tostring(err) end
    rodando = false
end

-- Depois de reconectar: espera carregar, vai ao dinheiro e equipa a esteira
local function posReconexao()
    config.rejoin = false
    salvarConfig()
    msg = "Reconectado: carregando..."
    local t0 = os.clock()
    local pronto = false
    while os.clock() - t0 < 60 and not encerrado do
        local _, hum, root = getChar()
        if hum and root then pronto = true break end
        task.wait(0.5)
    end
    if not pronto or encerrado then
        msg = "Reconectado, mas o personagem não carregou"
        return
    end
    task.wait(8) -- deixa o jogo terminar de carregar
    if moneyPos then
        sequenciaPosOvo(60)
    else
        msg = "Sem ponto do dinheiro: só equipando a esteira"
        garantirEsteira()
    end
end

local function iniciarEvento()
    estado = "evento"
    eventoInicio = os.time()
    eventoFim = eventoInicio + EVENT_DURATION
    msg = "Evento iniciado"
    task.spawn(function()
        task.wait(1.5)
        local s = timerLabel and timerLabel:IsDescendantOf(playerGui) and parseTime(timerLabel.Text)
        if estado == "evento" and s and s > 0 and s <= 600 then
            eventoFim = os.time() + s
        end
    end)
end

local function fimEvento()
    estado = "esperando"
    lastSecs = nil
    ultimaBolha = os.clock()
    task.spawn(sequenciaPosOvo)
end

local idleConn = player.Idled:Connect(function()
    if active then doClick() end
end)

-- Montagem da GUI
local function label(y, bold)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 0, 18)
    l.Position = UDim2.new(0, 8, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1, 1, 1)
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = frame
    return l
end

local function botao(y, texto, cor, lado)
    local b = Instance.new("TextButton")
    if lado then
        b.Size = UDim2.new(0.5, -12, 0, 26)
        b.Position = lado == 1 and UDim2.new(0, 8, 0, y) or UDim2.new(0.5, 4, 0, y)
    else
        b.Size = UDim2.new(1, -16, 0, 26)
        b.Position = UDim2.new(0, 8, 0, y)
    end
    b.Text = texto
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.new(1, 1, 1)
    b.BackgroundColor3 = cor
    b.BorderSizePixel = 0
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local titulo = label(6, true)
titulo.Text = "Farm Helper  |  F7 pausa  F8 sair"
titulo.TextColor3 = Color3.fromRGB(180, 180, 190)
local lStatus, lClick, lEvento, lTimer, lTimerInfo, lPonto, lClique, lMotivo, lRec, lMsg =
    label(30), label(48), label(66), label(84), label(102), label(120), label(138),
    label(156), label(174), label(192)

local bPonto = botao(220, "Gravar PONTO DO DINHEIRO", Color3.fromRGB(50, 150, 80))
local bTool = botao(250, "Gravar ESTEIRA (equipada)", Color3.fromRGB(60, 110, 190))
local bEvento = botao(280, "Evento começou", Color3.fromRGB(190, 130, 40), 1)
local bTimer = botao(280, "Trocar timer", Color3.fromRGB(90, 90, 110), 2)
local bTeste = botao(310, "Testar sequência", Color3.fromRGB(110, 80, 160), 1)
local bDiag = botao(310, "Diagnóstico", Color3.fromRGB(70, 130, 130), 2)
local bToggle = botao(346, "Pausar", Color3.fromRGB(170, 60, 60))

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 20, 0, 20)
close.Position = UDim2.new(1, -26, 0, 6)
close.BackgroundTransparency = 1
close.Text = "X"
close.TextColor3 = Color3.fromRGB(200, 90, 90)
close.Font = Enum.Font.GothamBold
close.TextSize = 14
close.Parent = frame

local function alternarPausa()
    active = not active
    if active then
        nextClick = os.clock() + INTERVAL
        ultimaBolha = os.clock()
        msg = "Retomado"
    else
        msg = "PAUSADO"
    end
end

bPonto.MouseButton1Click:Connect(function()
    local _, _, root = getChar()
    if root then
        moneyPos = root.Position
        msg = salvarConfig() and "Ponto gravado e salvo" or "Ponto gravado (sem arquivo)"
    end
end)
bTool.MouseButton1Click:Connect(function()
    local char = getChar()
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        toolName = tool.Name
        msg = (salvarConfig() and "Esteira salva: " or "Esteira: ") .. tool.Name
    else
        msg = "Equipe a esteira antes"
    end
end)
bEvento.MouseButton1Click:Connect(iniciarEvento)
bTimer.MouseButton1Click:Connect(function()
    timerList = acharTimers()
    if #timerList == 0 then timerLabel = nil; timerIdx = 0; return end
    timerIdx = (timerIdx % #timerList) + 1
    timerLabel = timerList[timerIdx]
end)
bDiag.MouseButton1Click:Connect(diagnostico)
bTeste.MouseButton1Click:Connect(function() task.spawn(sequenciaPosOvo) end)
bToggle.MouseButton1Click:Connect(alternarPausa)

local heartbeat, keyConn
local function encerrar()
    encerrado = true
    active = false
    pcall(function() idleConn:Disconnect() end)
    if heartbeat then heartbeat:Disconnect() end
    if keyConn then keyConn:Disconnect() end
    if env.FarmHelperEncerrar == encerrar then env.FarmHelperEncerrar = nil end
    gui:Destroy()
end
env.FarmHelperEncerrar = encerrar
close.MouseButton1Click:Connect(encerrar)

-- Atalhos de teclado
keyConn = UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == TECLA_PAUSA then
        alternarPausa()
    elseif input.KeyCode == TECLA_ENCERRAR then
        encerrar()
    end
end)

-- Arrastar
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position, frame.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- Motivo atual (mostra por que está clicando ou não)
local function motivoTexto(agora)
    if not active then return "PAUSADO: nada e clicado nem fechado (F7/botao retoma)" end
    if bloqueio then
        if compraAtual and compraAtual.fechar and tentativasFechar < 4 then
            return string.format("Fechando compra (%d/4): %s", tentativasFechar, bloqueio)
        end
        return "BLOQUEADO: " .. bloqueio
    end
    if reconectando then return "Reconectando ao jogo..." end
    if estado ~= "esperando" then return "Parado: evento do ovo em andamento" end
    if rodando then return "Parado: voltando ao dinheiro" end
    if not focado then return "Roblox sem foco (cliques podem falhar)" end
    if nVisiveis > 0 then
        local t = string.format("Clicando bolha (há %ds)", math.floor(agora - ultimoClique))
        if nPuladas > 0 and ultimoPulo then t = t .. " | pulou: " .. ultimoPulo end
        return t
    end
    if nRotulo > 0 then
        return string.format("Clicando botão por rótulo (%d)", nRotulo)
    end
    if nSemBotao > 0 then
        return string.format("%d pop-up(s) sem botão próprio (não clico)", nSemBotao)
    end
    if nPuladas > 0 and ultimoPulo then
        return "Pulando bolha: " .. ultimoPulo
    end
    if not CLICAR_BOLHAS then return "CLICAR_BOLHAS desligado" end
    return string.format("Sem alvos há %ds", math.floor(agora - ultimaBolha))
end

-- Loop principal (cada bloco roda isolado)
local lastPos
local tTimerScan, tAlvosBolha, tAlvosRotulo, tClick, tBloqueio = 0, 0, 0, 0, 0

heartbeat = RunService.Heartbeat:Connect(function()
    local agora = os.clock()
    local remaining = math.max(0, nextClick - agora)
    local secs = nil

    seguro("antiafk", function()
        if active and remaining <= 0 then
            task.spawn(doClick)
            nextClick = agora + INTERVAL
            remaining = INTERVAL
        end
    end)

    -- Janela de compra (a cada 0,25s): bloqueia os cliques e tenta fechar com o X.
    -- LIGADO AO PAUSAR: com o script PAUSADO (botão "Pausar" ou F7) ele não mexe em
    -- janela nenhuma, para você poder comprar em paz.
    if not active then
        if compraAtual or bloqueio or tentativasFechar > 0 then
            compraAtual, bloqueio, tentativasFechar = nil, nil, 0
        end
    elseif agora - tBloqueio > 0.25 then
        tBloqueio = agora
        local okB, resB = pcall(acharJanelaCompra)
        if okB then
            compraAtual = resB
            bloqueio = resB and resB.motivo or nil
        else
            compraAtual = nil
            bloqueio = "erro na verificação de compra"
        end
        if compraAtual then
            if tentativasFechar >= 4 and agora - ultimoFechar > 20 then tentativasFechar = 0 end
            if FECHAR_COMPRAS and compraAtual.fechar and tentativasFechar < 4
                and agora - ultimoFechar > 0.8 then
                ultimoFechar = agora
                task.spawn(fecharAgora, compraAtual)
            elseif FECHAR_COMPRAS and not compraAtual.fechar then
                msg = "Janela de compra aberta, mas não achei o X (use Diagnóstico)"
            elseif tentativasFechar >= 4 then
                msg = "Não consegui fechar a janela de compra: cliques bloqueados"
            end
        else
            tentativasFechar = 0
        end
    end

    seguro("timer", function()
        if agora - tTimerScan > 5 and not (timerLabel and timerLabel:IsDescendantOf(playerGui)) then
            tTimerScan = agora
            timerList = acharTimers()
            timerIdx = #timerList > 0 and 1 or 0
            timerLabel = timerList[timerIdx]
        end
        secs = timerLabel and timerLabel:IsDescendantOf(playerGui) and parseTime(timerLabel.Text) or nil
        if secs then lastSecs, lastSecsAt = secs, agora end
    end)

    seguro("estado", function()
        local _, _, root = getChar()
        local teleportou = false
        if root then
            if lastPos and (root.Position - lastPos).Magnitude > TELEPORT_DIST then teleportou = true end
            lastPos = root.Position
        else
            lastPos = nil
        end

        if active then
            if teleportou then
                if estado == "esperando" then
                    local armado = lastSecs and lastSecs <= ARMA_SEG and (agora - lastSecsAt) < ARMA_SEG * 1.5
                    if armado then
                        iniciarEvento()
                    else
                        msg = "Teleporte ignorado, timer em " .. (lastSecs and fmt(lastSecs) or "?")
                    end
                elseif estado == "evento" and os.time() - eventoInicio > 20 then
                    fimEvento()
                end
            end
            if estado == "evento" and os.time() >= eventoFim then
                fimEvento()
            end
        end

        -- Se a sequência travar, libera depois de 120s
        if rodando and agora - rodandoDesde > 120 then
            rodando = false
            msg = "Sequência travou: liberado"
        end
    end)

    seguro("cliques", function()
        if active and estado == "esperando" and not rodando and not bloqueio and not reconectando then
            -- 1) bolhas
            if CLICAR_BOLHAS and agora - tAlvosBolha > 0.3 then
                tAlvosBolha = agora
                refrescarAlvosBolha()
            end
            local lista, puladas, motivo = {}, 0, nil
            if CLICAR_BOLHAS then
                for _, b in ipairs(alvosBolha) do
                    local modo, why = avaliarAlvo(b)
                    if modo then
                        table.insert(lista, { b = b, base = modo })
                    else
                        puladas += 1
                        motivo = why
                    end
                end
            end
            nVisiveis = #lista
            nPuladas = puladas
            if puladas > 0 then ultimoPulo = motivo end
            if nVisiveis > 0 then ultimaBolha = agora end

            -- 2) botões por rótulo (só se não houver bolha)
            local doRotulo = false
            nRotulo = 0
            if #lista == 0 and #ROTULOS_CLICAR > 0 then
                if agora - tAlvosRotulo > 0.5 then
                    tAlvosRotulo = agora
                    alvosRotulo = acharBotoesPorRotulo()
                end
                for _, b in ipairs(alvosRotulo) do
                    if (agora - (ultimoRotulo[b] or -1000)) >= ROTULO_COOLDOWN then
                        local modo, why = avaliarAlvo(b)
                        if modo then
                            table.insert(lista, { b = b, base = modo })
                        else
                            nPuladas += 1
                            ultimoPulo = why
                        end
                    end
                end
                nRotulo = #lista
                doRotulo = nRotulo > 0
            end

            -- 3) clicar (até MAX_CLIQUES_POR_VEZ bolhas por rodada)
            if #lista > 0 and agora - tClick > CLICK_DELAY then
                tClick = agora
                local quantos = math.min(#lista, doRotulo and 1 or MAX_CLIQUES_POR_VEZ)
                for i = 1, quantos do
                    local item = lista[((rodizio + i - 1) % #lista) + 1]
                    if doRotulo then ultimoRotulo[item.b] = agora end
                    local forma = formaDoClique(item.b, item.base)
                    task.delay((i - 1) * 0.1, clicarGui, item.b, forma)
                end
                rodizio += quantos
            end
        else
            nVisiveis, nRotulo, nPuladas, nSemBotao = 0, 0, 0, 0
        end
    end)

    seguro("reequipar", function()
        if AUTO_REEQUIPAR and active and estado == "esperando" and not rodando and toolName
            and not reconectando and agora - ultimaBolha > SEM_BOLHA_SEG
            and agora - ultimoReequipe > 30 then
            local char, hum = getChar()
            if char and hum and not char:FindFirstChild(toolName) then
                local tool = player.Backpack:FindFirstChild(toolName)
                if tool then
                    hum:EquipTool(tool)
                    ultimoReequipe = agora
                    msg = "Esteira reequipada " .. os.date("%H:%M:%S")
                end
            end
        end
    end)

    seguro("ui", function()
        if agora - tCaps > 3 then
            tCaps = agora
            capsStr = capsTexto()
        end
        local rm = math.floor(remaining)
        lStatus.Text = active and "Status: ATIVO" or "Status: PAUSADO"
        lStatus.TextColor3 = active and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(220, 80, 80)
        lClick.Text = string.format("Anti-AFK em %02d:%02d | Cliques: %d", rm // 60, rm % 60, clicks)
        if estado == "evento" then
            lEvento.Text = "EVENTO: acaba em " .. fmt(eventoFim - os.time())
            lEvento.TextColor3 = Color3.fromRGB(255, 200, 60)
        else
            lEvento.Text = "Aguardando evento | Ciclos: " .. eggRuns
            lEvento.TextColor3 = Color3.new(1, 1, 1)
        end
        lTimer.Text = secs and ("Timer lido: " .. fmt(secs)) or "Timer: NÃO ACHADO (use botão manual)"
        lTimer.TextColor3 = secs and Color3.new(1, 1, 1) or Color3.fromRGB(255, 200, 60)
        if timerLabel and timerLabel:IsDescendantOf(playerGui) then
            lTimerInfo.Text = string.format("Timer %d/%d: %s.%s", timerIdx, #timerList,
                timerLabel.Parent and timerLabel.Parent.Name or "?", timerLabel.Name)
        else
            lTimerInfo.Text = "Nenhum texto com hora achado: use Diagnóstico"
        end
        lPonto.Text = "Dinheiro: " .. (moneyPos and "ok" or "NÃO") .. " | Esteira: " .. (toolName or "não gravada")
        lClique.Text = string.format("Cliques: %d | bolhas: %d%s%s%s", cliquesEsteira, nVisiveis,
            nPuladas > 0 and (" (+" .. nPuladas .. " puladas)") or "",
            nSemBotao > 0 and (" (+sem botão: " .. nSemBotao .. ")") or "",
            nRotulo > 0 and (" | rótulo: " .. nRotulo) or "")
        lMotivo.Text = motivoTexto(agora)
        if bloqueio then
            lMotivo.TextColor3 = Color3.fromRGB(230, 80, 80)
        elseif (nVisiveis > 0 or nRotulo > 0) and active then
            lMotivo.TextColor3 = Color3.fromRGB(80, 220, 120)
        else
            lMotivo.TextColor3 = Color3.fromRGB(255, 200, 60)
        end
        if reconectando then
            lRec.Text = string.format("Reconectando: tentativa %d/%d", tentativas, MAX_TENTATIVAS)
            lRec.TextColor3 = Color3.fromRGB(255, 200, 60)
        else
            lRec.Text = "Reconexão: " .. capsStr
            lRec.TextColor3 = (capsStr == "pronta") and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(255, 200, 60)
        end
        if ultimoErro and agora - erroEm < 20 then
            lMsg.Text = "ERRO " .. ultimoErro
            lMsg.TextColor3 = Color3.fromRGB(230, 80, 80)
        else
            lMsg.Text = msg
            lMsg.TextColor3 = Color3.new(1, 1, 1)
        end
        bToggle.Text = active and "Pausar" or "Ativar"
        bToggle.BackgroundColor3 = active and Color3.fromRGB(170, 60, 60) or Color3.fromRGB(50, 150, 80)
    end)
end)

-- INÍCIO: liga a detecção de desconexão e, se acabamos de reconectar, retoma o farm
task.spawn(ligarDeteccaoDesconexao)
if config.rejoin then
    if os.time() - (config.rejoinAt or 0) < 900 then
        task.spawn(posReconexao)
    else
        config.rejoin = false
        salvarConfig()
    end
end
