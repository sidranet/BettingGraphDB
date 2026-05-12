USE master;
GO
IF DB_ID('BettingGraphDB') IS NOT NULL
BEGIN
    ALTER DATABASE BettingGraphDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BettingGraphDB;
END
CREATE DATABASE BettingGraphDB;
GO
USE BettingGraphDB;
GO

DBCC FREEPROCCACHE;
GO

-- 1. Узлы
CREATE TABLE dbo.Player (
    PlayerID INT PRIMARY KEY, 
    FullName NVARCHAR(100), 
    Balance DECIMAL(10,2) DEFAULT 0
) AS NODE;

CREATE TABLE dbo.Match (
    MatchID INT PRIMARY KEY, 
    Sport NVARCHAR(50), 
    HomeTeam NVARCHAR(100), 
    AwayTeam NVARCHAR(100), 
    MatchDate DATE, 
    Status NVARCHAR(20) DEFAULT 'Scheduled'
) AS NODE;

CREATE TABLE dbo.Coefficient (
    CoeffID INT PRIMARY KEY, 
    MarketType NVARCHAR(50), 
    Value DECIMAL(4,2)
) AS NODE;

-- 2. Рёбра (ПРАВИЛЬНЫЙ СИНТАКСИС)
CREATE TABLE dbo.PlacesBet (
    BetID INT IDENTITY(1,1), 
    Amount DECIMAL(10,2) NOT NULL, 
    OddsValue DECIMAL(4,2) NOT NULL,
    BetDate DATE, 
    Status NVARCHAR(20) DEFAULT 'Pending'
) AS EDGE;

ALTER TABLE dbo.PlacesBet ADD CONSTRAINT EC_Player_Match CONNECTION (dbo.Player TO dbo.Match);

CREATE TABLE dbo.HasCoefficient (
    LinkID INT IDENTITY(1,1), 
    IsActive BIT DEFAULT 1
) AS EDGE;

ALTER TABLE dbo.HasCoefficient ADD CONSTRAINT EC_Match_Coefficient CONNECTION (dbo.Match TO dbo.Coefficient);

--отражает, насколько сильно игрок ориентируется на ставки и мнение другого игрока
CREATE TABLE dbo.FollowsPlayer (
    FollowID INT IDENTITY(1,1), 
    SinceDate DATE, 
    TrustWeight DECIMAL(3,2) DEFAULT 1.00
) AS EDGE;

ALTER TABLE dbo.FollowsPlayer ADD CONSTRAINT EC_Player_Player CONNECTION (dbo.Player TO dbo.Player);


-- 3. Заполнение узлов
INSERT INTO dbo.Player (PlayerID, FullName, Balance) VALUES
(1,'Иванов И.',5000),(2,'Петров А.',3200),(3,'Сидоров К.',8000),
(4,'Кузнецов М.',1500),(5,'Смирнов В.',12000),(6,'Попов Д.',4500),
(7,'Васильев Н.',6700),(8,'Новиков Е.',2000),(9,'Федоров Р.',9000),(10,'Морозов Л.',5500);

INSERT INTO dbo.Match (MatchID, Sport, HomeTeam, AwayTeam, MatchDate, Status) VALUES
(1,'Football','Спартак','Зенит','2024-10-01','Finished'),
(2,'Football','ЦСКА','Локо','2024-10-05','Finished'),
(3,'Tennis','Джокович','Надаль','2024-10-10','Scheduled'),
(4,'Basketball','Lakers','Warriors','2024-10-12','Scheduled'),
(5,'Hockey','СКА','ЦСКА','2024-10-15','Finished'),
(6,'Football','Реал','Барса','2024-10-20','Scheduled'),
(7,'Tennis','Медведев','Алькарас','2024-10-22','Scheduled'),
(8,'Basketball','Bulls','Celtics','2024-10-25','Scheduled'),
(9,'Hockey','Динамо','АкБарс','2024-10-28','Finished'),
(10,'Football','ManCity','Liverpool','2024-11-01','Scheduled');

INSERT INTO dbo.Coefficient (CoeffID, MarketType, Value) VALUES
(1,'Win1',1.85),(2,'Draw',3.40),(3,'Win2',4.10),(4,'TotalOver2.5',1.90),
(5,'Win1',2.20),(6,'TotalUnder2.5',1.95),(7,'Win2',3.80),(8,'Win1',1.50),
(9,'Draw',4.00),(10,'TotalOver1.5',1.75);

-- 4. Заполнение рёбер (ПРАВИЛЬНО)
INSERT INTO dbo.PlacesBet ($from_id, $to_id, Amount, OddsValue, BetDate, Status)
SELECT p.$node_id, m.$node_id, a, o, d, s 
FROM (VALUES
(1,1,500,1.85,'2024-09-30','Won'),
(1,2,300,3.40,'2024-09-30','Lost'),
(2,1,1000,1.85,'2024-10-01','Won'),
(2,3,400,4.10,'2024-10-11','Pending'),
(3,4,600,1.90,'2024-09-12','Lost'),
(3,5,200,2.20,'2024-10-12','Won'),
(4,6,800,1.95,'2024-10-14','Pending'),
(5,7,1500,3.80,'2024-10-20','Lost'),
(6,8,500,1.50,'2024-10-22','Won'),
(7,9,700,4.00,'2024-10-28','Lost'),
(8,10,900,1.75,'2024-10-30','Pending'),
(9,2,1200,3.40,'2024-09-30','Won'),
(10,4,400,1.90,'2024-09-12','Lost')
) v(pid, mid, a, o, d, s)
JOIN dbo.Player p ON p.PlayerID = v.pid 
JOIN dbo.Match m ON m.MatchID = v.mid;

INSERT INTO dbo.HasCoefficient ($from_id, $to_id, IsActive)
SELECT m.$node_id, c.$node_id, 1 
FROM dbo.Match m 
JOIN dbo.Coefficient c ON 
    (m.MatchID=1 AND c.CoeffID IN (1,2,3)) OR 
    (m.MatchID=3 AND c.CoeffID=5) OR 
    (m.MatchID=4 AND c.CoeffID=6) OR 
    (m.MatchID=6 AND c.CoeffID=8) OR 
    (m.MatchID=8 AND c.CoeffID=10);

INSERT INTO dbo.FollowsPlayer ($from_id, $to_id, SinceDate, TrustWeight)
SELECT p1.$node_id, p2.$node_id, '2024-01-01', tw 
FROM (VALUES
(1,2,0.9),(1,3,0.8),(2,4,0.7),(3,1,0.85),(4,5,0.6),
(5,6,0.95),(6,7,0.75),(7,8,0.8),(8,9,0.7),(9,10,0.88),(10,1,0.92)
) v(f, t, tw) 
JOIN dbo.Player p1 ON p1.PlayerID=v.f 
JOIN dbo.Player p2 ON p2.PlayerID=v.t;

-- 5. MATCH ЗАПРОСЫ (Цепочки из 3-х и более узлов)

-- Запрос 1: Найти все коэффициенты матчей, на которые ставил конкретный игрок
-- Цепочка: Player -> PlacesBet -> Match -> HasCoefficient -> Coefficient (4 узла)
SELECT p.FullName, m.HomeTeam, c.MarketType, c.Value
FROM dbo.Player p, dbo.PlacesBet b, dbo.Match m, dbo.HasCoefficient hc, dbo.Coefficient c
WHERE MATCH(p-(b)->m-(hc)->c) 
  AND p.PlayerID = 1;

-- Запрос 2: Поиск видов спорта, которыми интересуются "друзья" игрока
-- Цепочка: Player (подписчик) -> FollowsPlayer -> Player (кумир) -> PlacesBet -> Match (4 узла)
SELECT DISTINCT p_sub.FullName AS Subscriber, p_idol.FullName AS Idol, m.Sport
FROM dbo.Player p_sub, dbo.FollowsPlayer f, dbo.Player p_idol, dbo.PlacesBet b, dbo.Match m
WHERE MATCH(p_sub-(f)->p_idol-(b)->m)
  AND p_sub.PlayerID = 5;

-- Запрос 3: Поиск активных ставок через социальную сеть
-- Найти цепочку: кто на кого подписан и кто на какой исход (Win1/Win2) ставил
SELECT p1.FullName AS Follower, p2.FullName AS Star, c.MarketType, c.Value
FROM dbo.Player p1, dbo.FollowsPlayer f, dbo.Player p2, dbo.PlacesBet b, dbo.Match m, dbo.HasCoefficient hc, dbo.Coefficient c
WHERE MATCH(p1-(f)->p2-(b)->m-(hc)->c)
  AND c.Value > 2.0;

-- Запрос 4: Анализ цепочки доверия (транзитивная подписка)
-- Цепочка: Player1 -> Player2 -> Player3 (3 узла)
SELECT p1.FullName AS StartNode, p2.FullName AS MiddleNode, p3.FullName AS EndNode
FROM dbo.Player p1, dbo.FollowsPlayer f1, dbo.Player p2, dbo.FollowsPlayer f2, dbo.Player p3
WHERE MATCH(p1-(f1)->p2-(f2)->p3)
  AND p1.PlayerID = 1;

-- Запрос 5: Поиск потенциально выигрышных матчей у тех, за кем мы следим
SELECT p1.FullName AS Me, p2.FullName AS Expert, m.HomeTeam, b.Amount
FROM dbo.Player p1, dbo.FollowsPlayer f, dbo.Player p2, dbo.PlacesBet b, dbo.Match m
WHERE MATCH(p1-(f)->p2-(b)->m)
  AND b.Status = 'Won';


-- 6. SHORTEST_PATH ЗАПРОСЫ (Рекурсивный поиск путей)

-- Запрос 1: Кратчайший путь любой длины (+) от Иванова до Морозова
-- Требование: использование STRING_AGG и LAST_VALUE (аналог LAST_NODE)
SELECT 
    StartPlayer, 
    EndPlayer, 
    Path
FROM (
    SELECT 
        p1.FullName AS StartPlayer,
        LAST_VALUE(p2.FullName) WITHIN GROUP (GRAPH PATH) AS EndPlayer,
        LAST_VALUE(p2.PlayerID) WITHIN GROUP (GRAPH PATH) AS EndID,
        STRING_AGG(p2.FullName, ' -> ') WITHIN GROUP (GRAPH PATH) AS Path
    FROM 
        dbo.Player AS p1, 
        dbo.Player FOR PATH AS p2, 
        dbo.FollowsPlayer FOR PATH AS f
    WHERE MATCH(SHORTEST_PATH(p1(-(f)->p2)+))
      AND p1.PlayerID = 1
) AS Result
WHERE EndID = 10;

-- Запрос 2: Путь длиной от 1 до 10 шагов {1,10}
-- Требование: Вывод имен всех промежуточных узлов
SELECT 
    Path,
    Steps
FROM (
    SELECT 
        p1.FullName AS StartPlayer,
        LAST_VALUE(p2.PlayerID) WITHIN GROUP (GRAPH PATH) AS EndID,
        COUNT(p2.PlayerID) WITHIN GROUP (GRAPH PATH) AS Steps,
        STRING_AGG(p2.FullName, ' -> ') WITHIN GROUP (GRAPH PATH) AS Path
    FROM 
        dbo.Player AS p1, 
        dbo.Player FOR PATH AS p2, 
        dbo.FollowsPlayer FOR PATH AS f
    WHERE MATCH(SHORTEST_PATH(p1(-(f)->p2){1,10}))
      AND p1.PlayerID = 1
) AS Result
WHERE EndID = 10;