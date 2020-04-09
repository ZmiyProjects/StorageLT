USE master
GO
-- DROP DATABASE StorageLT

CREATE DATABASE StorageLT
GO
USE StorageLT
GO

CREATE SCHEMA HR
GO
CREATE SCHEMA Wares
GO

CREATE TABLE Wares.Product(
    ProductId INT PRIMARY KEY IDENTITY,
    ProductName VARCHAR(50) UNIQUE NOT NULL,
    Weight NUMERIC(7, 2) NOT NULL,
    Length NUMERIC(5, 2) NOT NULL,
    Height NUMERIC(5, 2) NOT NULL,
    Width NUMERIC(5, 2) NOT NULL,
    CONSTRAINT CK_Weight CHECK (Weight > 0),
    CONSTRAINT CK_Length CHECK (Length > 0),
    CONSTRAINT CK_Height CHECK (Height > 0),
    CONSTRAINT CK_Width CHECK (Width > 0),
    CONSTRAINT CK_ProductName CHECK (ProductName <> '')
);

CREATE TABLE Wares.Storage(
    StorageId INT PRIMARY KEY IDENTITY,
    StorageAddress VARCHAR(255) UNIQUE NOT NULL,
    CONSTRAINT CK_StorageAddress CHECK (StorageAddress <> '')
);

CREATE TABLE Wares.Accommodation(
    StorageId INT NOT NULL REFERENCES Wares.Storage(StorageId),
    ProductId INT NOT NULL REFERENCES Wares.Product(ProductId),
    Quantity SMALLINT NOT NULL,
    CONSTRAINT CK_Quantity CHECK (Quantity >= 0),
    CONSTRAINT PK_Accommodation PRIMARY KEY (StorageId, ProductId)
);

CREATE TABLE HR.Position(
    PositionId INT PRIMARY KEY IDENTITY,
    PositionName VARCHAR(50),
    Salary NUMERIC(9, 2),
    CONSTRAINT CK_PositionName CHECK (PositionName <> ''),
    CONSTRAINT CK_Salary CHECK (Salary BETWEEN 10000 AND 200000)
);

CREATE TABLE HR.Employee(
    EmployeeId INT PRIMARY KEY IDENTITY,
    LastName VARCHAR(50) NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    BirthDate DATE NOT NULL,
    HireDate DATE NOT NULL DEFAULT GETDATE(),
    PositionId INT NOT NULL REFERENCES HR.Position(PositionId),
    CONSTRAINT CK_LastName CHECK ( LastName <> '' ),
    CONSTRAINT CK_FirstName CHECK ( FirstName <> '' ),
    CONSTRAINT CK_BirthDate CHECK (
        IIF(DATEADD(year, -DATEDIFF(year, BirthDate, GETDATE()), GETDATE()) < BirthDate,
        DATEDIFF(year, BirthDate, GETDATE())-1,
        DATEDIFF(year, BirthDate, GETDATE())) >= 18 )
);

CREATE TABLE HR.Interchange(
    InterchangeId INT PRIMARY KEY IDENTITY,
    IBegin SMALLDATETIME NOT NULL,
    IEnd SMALLDATETIME NOT NULL,
    StorageId INT NOT NULL REFERENCES Wares.Storage(StorageId),
    CONSTRAINT CK_Dates CHECK ( DATEDIFF(MINUTE, IBegin, IEnd) BETWEEN 480 AND 1440)
);

CREATE TABLE HR.Appointment(
    EmployeeId INT REFERENCES HR.Employee(EmployeeId),
    InterchangeId INT REFERENCES HR.Interchange(InterchangeId),
    CONSTRAINT PK_Appointment PRIMARY KEY (EmployeeId, InterchangeId)
);

GO
-- Получить
CREATE OR ALTER FUNCTION HR.previous_inter(@EmployeeId INT) RETURNS TABLE AS
  RETURN (
    SELECT E.EmployeeId, I.IEnd FROM HR.Employee AS E
        jOIN HR.Appointment AS A ON E.EmployeeId = A.EmployeeId
	    JOIN HR.Interchange AS I ON A.InterchangeId = I.InterchangeId
	WHERE E.EmployeeId = @EmployeeId
	ORDER BY I.IEnd DESC
    OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY );
GO
-- Возвращает количество товаров на всех складах
CREATE FUNCTION Wares.all_products() RETURNS TABLE AS
    RETURN (
        SELECT P.ProductName, S.StorageAddress, ISNULL(A.Quantity, 0) FROM Wares.Storage As S
            CROSS JOIN Wares.Product AS P
            LEFT OUTER JOIN Wares.Accommodation AS A ON S.StorageId = A.StorageId AND P.ProductId = A.ProductId);
GO
-- Возвращает суммарное количество определенного товара с учетом всех складов
CREATE FUNCTION Wares.product_quantity(@ProductId INT) RETURNS INT AS
    BEGIN
        RETURN (SELECT SUM(Quantity) FROM Accommodation WHERE ProductId = @ProductId);
    END
GO
-- Возвращает суммарное количество определенного товара с учетом всех складов в виде строки формата
-- <название товара>: <количество>
CREATE FUNCTION Wares.product_quantity_string(@ProductId INT) RETURNS VARCHAR(5) AS
    BEGIN
        RETURN (
            SELECT  CONCAT(P.ProductName, ': ', CAST(SUM(Quantity) AS VARCHAR(5))) FROM Wares.Accommodation AS A
                JOIN Wares.Product AS P ON P.ProductId = A.ProductId AND P.ProductId = @ProductId
            GROUP BY P.ProductName
            );
    END
GO
CREATE OR ALTER TRIGGER HR.check_interchange ON HR.Interchange AFTER INSERT, UPDATE AS
    BEGIN
	  IF EXISTS (
        SELECT * FROM HR.Interchange AS H
             JOIN inserted AS I ON I.InterchangeId <> H.InterchangeId AND I.StorageId = H.StorageId
             WHERE  (I.IBegin BETWEEN H.IBegin AND H.IEnd) OR (I.IEnd BETWEEN H.IBegin AND H.IEnd))
	  THROW 51001, N'Недопустимый диапозон дат!', 10;
    END
GO
CREATE OR ALTER TRIGGER HR.check_previous_inter ON HR.Appointment AFTER INSERT, UPDATE AS
    BEGIN
          IF EXISTS(
            SELECT I.EmployeeId, P.IEnd, IC.IBegin, IC.IEnd, DATEDIFF(MINUTE, P.IEnd, IC.IBegin) FROM inserted AS I
                CROSS APPLY HR.previous_inter(I.EmployeeId) AS P
                JOIN HR.Interchange AS IC ON I.InterchangeId = IC.InterchangeId
            WHERE ABS(DATEDIFF(MINUTE, P.IEnd, IC.IBegin)) < 479)
          THROW 51002, N'Интервал между сменами долже состалеть не менее 7 часов 59 минут!', 10;
    END
GO
-- Внесение данных в БД
-- Должность/позиции
INSERT INTO HR.Position(PositionName, Salary) VALUES (N'Кладовщик', 20000);
INSERT INTO HR.Position(PositionName, Salary) VALUES (N'Комплектовщик', 40000);
INSERT INTO HR.Position(PositionName, Salary) VALUES (N'Упаковщик', 25000);
INSERT INTO HR.Position(PositionName, Salary) VALUES (N'Грузчик', 25000);

-- Сотрудники
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Сергей', N'Иванов', '1999.03.08', 1, '2019.10.28');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Михаил', N'Алексеев', '2000.09.23', 1, '2020.01.15');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Иван', N'Андреев', '1994.02.22', 1, '2018.05.13');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Сергей', N'Петров', '1978.03.20', 2, '2018.11.04');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Сергей', N'Алексеев', '1984.10.02', 4, '2019.05.12');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Иван', N'Иванов', '1993.11.18', 3, '2019.08.25');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Дмитрий', N'Зубров', '1990.08.15', 2, '2018.02.14');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Николай', N'Волков', '1994.09.02', 4, '2019.11.23');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Алексей', N'Петров', '1997.08.08', 4, '2019.02.11');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Сергей', N'Иванов', '1979.04.19', 3, '2018.04.12');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Геннадий', N'Иванов', '1990.09.14', 2, '2017.10.22');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Владислав', N'Шилов', '1970.07.02', 2, '2018.05.10');
INSERT INTO HR.Employee(LastName, FirstName, BirthDate, PositionId, HireDate) VALUES (N'Кирилл', N'Полев', '1994.03.08', 1, '2019.11.29');

-- Товары
INSERT INTO Wares.Product(ProductName, Weight, Length, Height, Width) VALUES(N'Стол раскладной Arika', 75.8, 140, 75, 80);
INSERT INTO Wares.Product(ProductName, Weight, Length, Height, Width) VALUES(N'Стол Locarno cappuccino', 24.92, 100, 75, 100);
INSERT INTO Wares.Product(ProductName, Weight, Length, Height, Width) VALUES(N'Комод Loft REG1D1S/90 дуб вотан', 41.8, 92, 120.5, 38.5);
INSERT INTO Wares.Product(ProductName, Weight, Length, Height, Width) VALUES(N'Банкетка Viera серая', 4.9, 40, 40, 40);
INSERT INTO Wares.Product(ProductName, Weight, Length, Height, Width) VALUES(N'Обувница Art moon Calgary', 0.35, 42, 47.5, 19.5);

-- Склады
INSERT INTO Wares.Storage(StorageAddress) VALUES (N'Люблинская ул., д.80, корп. 4')
INSERT INTO Wares.Storage(StorageAddress) VALUES (N'Автомобильный пр., д.5, стр. 8')
INSERT INTO Wares.Storage(StorageAddress) VALUES (N'Ферганская ул., д.28, корп. 10')

-- Нахождение товаров на складе
INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(1, 1, 30);
INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(3, 1, 3);

INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(1, 2, 4);
INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(2, 2, 9);
INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(3, 2, 2);

INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(2, 4, 8);

INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(2, 5, 1);
INSERT INTO Wares.Accommodation(StorageId, ProductId, Quantity) VALUES(3, 5, 9);

-- Смены
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200202 14:30', '20200203 00:30', 1)
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200203 1:00', '20200203 10:00', 1)
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200203 11:00', '20200204 00:00', 1)

INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200202 14:30', '20200203 00:30', 2)
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200203 1:00', '20200203 10:00', 2)
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200203 11:00', '20200204 00:00', 2)

INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200202 14:30', '20200203 00:30', 3)
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200203 1:00', '20200203 10:00', 3)
INSERT INTO HR.Interchange(IBegin, IEnd, StorageId) VALUES('20200203 11:00', '20200204 00:00', 3)

-- Назначение сотрудников на смены
-- Смены для первого склада
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(1, 1);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(2, 1);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(13, 1);

INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(3, 2);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(4, 2);

INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(1, 3);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(2, 3);

-- Смены для второго склада
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(5, 4);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(6, 4);

INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(7, 5);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(8, 5);

INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(5, 6);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(6, 6);

-- Смены для третьего склада
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(9, 7);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(10, 7);

INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(11, 8);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(12, 8);

INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(9, 9);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(10, 9);
INSERT INTO HR.Appointment(EmployeeId, InterchangeId) VALUES(13, 9);

-- Создание логинов и пользователей
CREATE LOGIN StorageLTManager WITH
    PASSWORD = 'manager',
    DEFAULT_DATABASE = StorageLT;

CREATE LOGIN StorageLTOperator WITH
    PASSWORD = 'operator',
    DEFAULT_DATABASE = StorageLT;

CREATE LOGIN StorageLTCustomer WITH
    PASSWORD = 'customer',
    DEFAULT_DATABASE = StorageLT;

CREATE USER Manager FOR LOGIN StorageLTManager;

CREATE USER Operator FOR LOGIN StorageLTOperator;

CREATE USER Customer FOR LOGIN StorageLTCustomer;

-- определение прав доступа
-- Operator
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Wares TO Operator;
DENY UPDATE, DELETE ON Wares.Storage TO Operator;

-- Manager
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::HR TO Manager;
DENY INSERT, UPDATE, DELETE ON HR.Position TO Manager;
DENY UPDATE ON HR.Employee(HireDate, BirthDate) TO Manager;
GRANT SELECT ON Wares.Storage TO Manager;

-- Customer
GRANT EXECUTE ON Wares.all_products TO Customer;
GRANT SELECT ON Wares.product_quantity TO Customer;
GRANT SELECT ON Wares.product_quantity_string TO Customer;