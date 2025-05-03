-- Решаем AD-HOC задачи.
-- Задача 1. Время активности объявлений.
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем все объявления о проданных квартирах в городах без выбросов:
right_info AS (
SELECT *
FROM real_estate.flats AS f
JOIN real_estate.advertisement AS a USING(id)
JOIN real_estate.type t USING(type_id)
JOIN real_estate.city c USING(city_id)
WHERE id IN (SELECT * FROM filtered_id) AND days_exposition IS NOT NULL AND TYPE = 'город'
),
-- Откатегорируем все значения и посчитаем цену за квадратный метр:
categories AS (
SELECT 
		*,
		CASE 
			WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл' 
		END AS loc,
		CASE WHEN days_exposition >= 1 AND days_exposition <= 30 THEN 'до месяца'
		WHEN days_exposition > 30 AND days_exposition <= 90 THEN 'до трёх месяцев'
		WHEN days_exposition > 90 AND days_exposition <= 180 THEN 'до полугода'
		ELSE 'больше полугода'
		END AS segment_of_activity,
		ROUND((last_price/total_area)::NUMERIC, 2) AS cost_for_metr
FROM right_info 
)
SELECT
		loc AS "Регион",
		segment_of_activity AS "Сегмент активности",
		COUNT(id) AS "Количество объявлений",
		ROUND(COUNT(id)*100/(SUM(COUNT(id)) OVER (PARTITION BY loc)),2) AS "Доля объявлений от общего числа в регионе, %",
		ROUND(AVG(last_price)::NUMERIC, 2) AS "Средняя стоимость",
		ROUND(AVG(total_area)::numeric, 2) AS "Средняя площадь",
		ROUND(AVG(cost_for_metr)::NUMERIC, 2) AS "Средняя стоимость за метр",
		PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY rooms) AS "Медиана количества комнат",
		PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floor) AS "Медиана высоты этажа",
		PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY balcony) AS "Медиана количества балконов",
		ROUND((SUM(is_apartment)/COUNT(is_apartment)::NUMERIC)*100,2) AS "Доля апартаментов, %",
		ROUND((SUM(open_plan)/COUNT(open_plan)::NUMERIC)*100, 2) AS "Доля открытых планировок, %"
FROM categories 
GROUP BY loc, segment_of_activity
ORDER BY loc,
   		CASE segment_of_activity
      	WHEN 'до месяца' THEN 1
        WHEN 'до трёх месяцев' THEN 2
        WHEN 'до полугода' THEN 3
        ELSE 4
   		END;
-- Задача 2. Сезонность объявлений.
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем все объявления о проданных квартирах без выбросов, с указанием даты публикации, даты продажи, площади, 
-- стоимости за квадратный метр, оставив только объявления за период с 2015 по 2018 года включительно:
right_info AS (
SELECT 	id,
		first_day_exposition,
		(first_day_exposition + (days_exposition * INTERVAL '1 day'))::date AS last_day_exposition,
		total_area,
		last_price/total_area AS cpm
FROM real_estate.advertisement AS a 
JOIN real_estate.flats AS f USING(id)
WHERE id IN (SELECT * FROM filtered_id) 
AND days_exposition IS NOT NULL 
AND first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
AND (first_day_exposition + (days_exposition * INTERVAL '1 day'))::date BETWEEN '2015-01-01' AND '2018-12-31'
),
-- Статистика по публикациям по месяцам
publications_stats AS (
SELECT
		EXTRACT(MONTH FROM first_day_exposition) AS month,
		COUNT(id) AS publications_count
FROM right_info
GROUP BY 1
),
-- Статистика по продажам по месяцам
sales_stats AS (
SELECT
		EXTRACT(MONTH FROM last_day_exposition) AS month,
		COUNT(id) AS sales_count
FROM right_info
GROUP BY 1
)
-- Итоговый результат с объединением статистик
SELECT 
    p.month AS "Месяц",
    p.publications_count AS "Количество публикаций",
    s.sales_count AS "Количество продаж",
    (SELECT ROUND(AVG(total_area)::numeric,2) FROM right_info 
     WHERE EXTRACT(MONTH FROM first_day_exposition) = p.month) AS "Средняя площадь",
    (SELECT ROUND(AVG(cpm)::numeric,2) FROM right_info 
     WHERE EXTRACT(MONTH FROM first_day_exposition) = p.month) AS "Средняя цена за кв. м."
FROM publications_stats p
JOIN sales_stats s USING(month)
ORDER BY 1;
-- 3. Анализ рынка недвижимости Ленобласти
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем все объявления без выбросов с указанием локации (СПБ или Лен.область):
right_info AS (
SELECT 
		*,
		CONCAT(type,' ', city) AS full_name,
		ROUND((last_price/total_area)::NUMERIC, 2) AS cost_for_metr,
		CASE 
			WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл' 
		END AS loc
FROM real_estate.flats AS f
JOIN real_estate.advertisement AS a USING(id)
JOIN real_estate.type t USING(type_id)
JOIN real_estate.city c USING(city_id)
WHERE id IN (SELECT * FROM filtered_id)
),
-- Посчитаем статистику по опубликованным объявлениям:
public AS (
SELECT 
		full_name,
		COUNT(id) AS total_public,
		ROUND(COUNT(id)*100/(SUM(COUNT(id)) OVER (PARTITION BY loc)),2) AS perc_public,
		ROUND(AVG(total_area)::numeric, 2) AS avg_area,
		ROUND(AVG(cost_for_metr)::NUMERIC, 2) AS avg_cost_for_metr
FROM right_info 
WHERE loc = 'ЛенОбл'
GROUP BY 1, loc
),
-- Посчитаем статистику о проданных объектах:
sold AS (
SELECT 
		full_name,
		CEIL(AVG(days_exposition)) AS avg_d,
		COUNT(id) AS total_sold,
		ROUND(COUNT(id)*100/(SUM(COUNT(id)) OVER (PARTITION BY loc)),2) AS perc_sold
FROM right_info 
WHERE loc = 'ЛенОбл'
AND days_exposition IS NOT NULL
GROUP BY 1, loc
)
-- Основной запрос для определения ТОП-15 населеных пунктов:
SELECT 
		full_name AS "Наименование населеного пункта",
		total_public AS "Количество опубликованных объявлений",
		perc_public AS "Доля от всех публикаций",
		total_sold AS "Количество проданных объектов",
		perc_sold AS "Доля от всех продаж",
		avg_d AS "Средняя продолжительность публикации",
		avg_area AS "Средняя площадь",
		avg_cost_for_metr AS "Средняя стоимость за метр"
FROM public
FULL JOIN sold USING(full_name)
ORDER BY 2 DESC
LIMIT 15;





