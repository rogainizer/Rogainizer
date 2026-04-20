import { Router } from 'express';
import pool from '../config/db.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

const fixedCategoryColumns = ['MJ', 'SCH', 'WJ', 'XJ', 'MO', 'WO', 'XO', 'MV', 'WV', 'XV', 'MSV', 'WSV', 'XSV', 'MUV', 'WUV', 'XUV'];

function toNullableNumber(value) {
  if (value === '' || value === null || value === undefined) {
    return null;
  }

  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? numericValue : null;
}

function detectResultCategory(row) {
  return fixedCategoryColumns.find((category) => {
    const rawValue = Number(row?.[`${category.toLowerCase()}_raw`] ?? 0);
    const scaledValue = Number(row?.[`${category.toLowerCase()}_scaled`] ?? 0);
    return (Number.isFinite(rawValue) && rawValue !== 0) || (Number.isFinite(scaledValue) && scaledValue !== 0);
  }) || '';
}

async function ensureEventExists(eventId) {
  const [eventRows] = await pool.query(
    'SELECT id FROM events WHERE id = ? LIMIT 1',
    [eventId]
  );

  return Boolean(eventRows[0]);
}

router.get('/', async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT
         id,
         year,
         series,
         name,
         DATE_FORMAT(date, '%Y-%m-%d') AS date,
         organiser,
         duration_hours AS duration
       FROM events
       ORDER BY year ASC, series ASC, date ASC, id ASC`
    );
    res.json(rows);
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'events table does not exist. Run backend/sql/init.sql first.'
      });
    }
    res.status(500).json({ message: error.message });
  }
});

router.get('/:eventId/results', async (req, res) => {
  const eventId = Number(req.params.eventId);

  if (!Number.isInteger(eventId) || eventId <= 0) {
    return res.status(400).json({ message: 'eventId must be a positive integer' });
  }

  try {
    const [eventRows] = await pool.query(
      `SELECT
         id,
         year,
         series,
         name,
         DATE_FORMAT(date, '%Y-%m-%d') AS date
       FROM events
       WHERE id = ?
       LIMIT 1`,
      [eventId]
    );

    const event = eventRows[0];
    if (!event) {
      return res.status(404).json({ message: 'Event not found.' });
    }

    const [rows] = await pool.query(
      `SELECT
         id,
         team_name,
         team_member,
         final_score_raw,
         final_score_scaled,
         mj_raw, mj_scaled,
         sch_raw, sch_scaled,
         wj_raw, wj_scaled,
         xj_raw, xj_scaled,
         mo_raw, mo_scaled,
         wo_raw, wo_scaled,
         xo_raw, xo_scaled,
         mv_raw, mv_scaled,
         wv_raw, wv_scaled,
         xv_raw, xv_scaled,
         msv_raw, msv_scaled,
         wsv_raw, wsv_scaled,
         xsv_raw, xsv_scaled,
         muv_raw, muv_scaled,
         wuv_raw, wuv_scaled,
         xuv_raw, xuv_scaled
       FROM results
       WHERE event_id = ?
       ORDER BY team_name ASC, team_member ASC`,
      [eventId]
    );

    return res.json({ event, rows });
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.delete('/:eventId/results/delete-single-name-members', requireAuth, async (req, res) => {
  const eventId = Number(req.params.eventId);

  if (!Number.isInteger(eventId) || eventId <= 0) {
    return res.status(400).json({ message: 'eventId must be a positive integer' });
  }

  try {
    const eventExists = await ensureEventExists(eventId);
    if (!eventExists) {
      return res.status(404).json({ message: 'Event not found.' });
    }

    const [result] = await pool.query(
      `DELETE FROM results
       WHERE event_id = ?
         AND team_member IS NOT NULL
         AND TRIM(team_member) <> ''
         AND TRIM(team_member) NOT REGEXP '[[:space:]]'`,
      [eventId]
    );

    const deletedCount = Number(result?.affectedRows ?? 0);

    return res.json({
      message: deletedCount > 0
        ? `Deleted ${deletedCount} single-name result row${deletedCount === 1 ? '' : 's'}.`
        : 'No single-name result rows found for this event.',
      deletedCount
    });
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.put('/:eventId/results/:resultId', requireAuth, async (req, res) => {
  const eventId = Number(req.params.eventId);
  const resultId = Number(req.params.resultId);
  const teamName = String(req.body?.team_name || '').trim();
  const teamMember = String(req.body?.team_member || '').trim();
  const category = String(req.body?.category || '').trim().toUpperCase();

  if (!Number.isInteger(eventId) || eventId <= 0) {
    return res.status(400).json({ message: 'eventId must be a positive integer' });
  }

  if (!Number.isInteger(resultId) || resultId <= 0) {
    return res.status(400).json({ message: 'resultId must be a positive integer' });
  }

  if (!teamMember) {
    return res.status(400).json({ message: 'team_member is required' });
  }

  if (!fixedCategoryColumns.includes(category)) {
    return res.status(400).json({ message: 'category must be one of the fixed category columns' });
  }

  try {
    const [existingRows] = await pool.query(
      `SELECT
         id,
         mj_raw, mj_scaled,
         sch_raw, sch_scaled,
         wj_raw, wj_scaled,
         xj_raw, xj_scaled,
         mo_raw, mo_scaled,
         wo_raw, wo_scaled,
         xo_raw, xo_scaled,
         mv_raw, mv_scaled,
         wv_raw, wv_scaled,
         xv_raw, xv_scaled,
         msv_raw, msv_scaled,
         wsv_raw, wsv_scaled,
         xsv_raw, xsv_scaled,
         muv_raw, muv_scaled,
         wuv_raw, wuv_scaled,
         xuv_raw, xuv_scaled
       FROM results
       WHERE id = ?
         AND event_id = ?
       LIMIT 1`,
      [resultId, eventId]
    );

    const existingRow = existingRows[0];
    if (!existingRow) {
      return res.status(404).json({ message: 'Result row not found for this event.' });
    }

    const currentCategory = detectResultCategory(existingRow);
    const categoryAssignments = [];
    const queryValues = [teamName, teamMember];

    for (const fixedCategory of fixedCategoryColumns) {
      const rawColumn = `${fixedCategory.toLowerCase()}_raw`;
      const scaledColumn = `${fixedCategory.toLowerCase()}_scaled`;
      const rawValue = existingRow[rawColumn] ?? null;
      const scaledValue = existingRow[scaledColumn] ?? null;

      if (fixedCategory === category) {
        const nextRawValue = currentCategory === category ? rawValue : (currentCategory ? existingRow[`${currentCategory.toLowerCase()}_raw`] ?? null : null);
        const nextScaledValue = currentCategory === category ? scaledValue : (currentCategory ? existingRow[`${currentCategory.toLowerCase()}_scaled`] ?? null : null);
        categoryAssignments.push(`${rawColumn} = ?`, `${scaledColumn} = ?`);
        queryValues.push(nextRawValue, nextScaledValue);
        continue;
      }

      if (fixedCategory === currentCategory && currentCategory !== category) {
        categoryAssignments.push(`${rawColumn} = ?`, `${scaledColumn} = ?`);
        queryValues.push(null, null);
        continue;
      }

      categoryAssignments.push(`${rawColumn} = ?`, `${scaledColumn} = ?`);
      queryValues.push(rawValue, scaledValue);
    }

    const [result] = await pool.query(
      `UPDATE results
       SET
         team_name = ?,
         team_member = ?,
         ${categoryAssignments.join(',\n         ')}
       WHERE id = ?
         AND event_id = ?`,
      [...queryValues, resultId, eventId]
    );

    if (!result?.affectedRows) {
      return res.status(404).json({ message: 'Result row not found for this event.' });
    }

    return res.json({ message: 'Result row updated successfully.' });
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.delete('/:eventId/results/:resultId', requireAuth, async (req, res) => {
  const eventId = Number(req.params.eventId);
  const resultId = Number(req.params.resultId);

  if (!Number.isInteger(eventId) || eventId <= 0) {
    return res.status(400).json({ message: 'eventId must be a positive integer' });
  }

  if (!Number.isInteger(resultId) || resultId <= 0) {
    return res.status(400).json({ message: 'resultId must be a positive integer' });
  }

  try {
    const [result] = await pool.query(
      `DELETE FROM results
       WHERE id = ?
         AND event_id = ?`,
      [resultId, eventId]
    );

    if (!result?.affectedRows) {
      return res.status(404).json({ message: 'Result row not found for this event.' });
    }

    return res.json({ message: 'Result row deleted successfully.' });
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.post('/save-result', requireAuth, async (req, res) => {
  const {
    year,
    series,
    name,
    date,
    organiser,
    duration,
    overwrite = false
  } = req.body;

  const eventYear = Number(year);
  const durationHours = Number(duration);

  if (!Number.isInteger(eventYear) || eventYear <= 0) {
    return res.status(400).json({ message: 'year must be a positive integer' });
  }

  if (!series || !name || !date || !organiser || !Number.isFinite(durationHours)) {
    return res.status(400).json({
      message: 'year, series, name, date, organiser, and duration are required'
    });
  }

  try {
    const [existingRows] = await pool.query(
      `SELECT id
       FROM events
       WHERE year = ? AND series = ? AND name = ?
       LIMIT 1`,
      [eventYear, series, name]
    );

    const existingEvent = existingRows[0] || null;

    if (existingEvent && !overwrite) {
      return res.status(409).json({
        message: 'Event already exists. Confirm overwrite to continue.',
        exists: true
      });
    }

    let eventId;

    if (existingEvent) {
      await pool.query(
        `UPDATE events
         SET date = ?, organiser = ?, duration_hours = ?, year = ?, series = ?, name = ?
         WHERE id = ?`,
        [date, organiser, durationHours, eventYear, series, name, existingEvent.id]
      );
      eventId = existingEvent.id;
    } else {
      const [insertResult] = await pool.query(
        `INSERT INTO events (
          name,
          year,
          series,
          date,
          organiser,
          duration_hours
        ) VALUES (?, ?, ?, ?, ?, ?)`,
        [name, eventYear, series, date, organiser, durationHours]
      );
      eventId = insertResult.insertId;
    }

    const [savedRows] = await pool.query(
      `SELECT
        id,
        year,
        series,
        name,
        DATE_FORMAT(date, '%Y-%m-%d') AS date,
        organiser,
        duration_hours AS duration
       FROM events
       WHERE id = ?`,
      [eventId]
    );

    return res.json({
      message: existingEvent ? 'Event overwritten successfully.' : 'Event saved successfully.',
      event: savedRows[0]
    });
  } catch (error) {
    if (error.code === 'ER_BAD_FIELD_ERROR') {
      return res.status(500).json({
        message: 'events table schema is missing required columns. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.post('/:eventId/transformed-results', requireAuth, async (req, res) => {
  const eventId = Number(req.params.eventId);
  const rows = Array.isArray(req.body?.rows) ? req.body.rows : [];

  if (!Number.isInteger(eventId) || eventId <= 0) {
    return res.status(400).json({ message: 'eventId must be a positive integer' });
  }

  if (rows.length === 0) {
    return res.status(400).json({ message: 'rows must be a non-empty array' });
  }

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [eventRows] = await connection.query('SELECT id FROM events WHERE id = ? LIMIT 1', [eventId]);
    if (!eventRows[0]) {
      await connection.rollback();
      return res.status(404).json({ message: 'Event not found. Save event details first.' });
    }

    await connection.query('DELETE FROM results WHERE event_id = ?', [eventId]);

    const categoryValuePlaceholders = fixedCategoryColumns.map(() => '?, ?').join(', ');

    const insertSql = `INSERT INTO results (
      event_id,
      team_name,
      team_member,
      final_score_raw,
      final_score_scaled,
      mj_raw, mj_scaled,
      sch_raw, sch_scaled,
      wj_raw, wj_scaled,
      xj_raw, xj_scaled,
      mo_raw, mo_scaled,
      wo_raw, wo_scaled,
      xo_raw, xo_scaled,
      mv_raw, mv_scaled,
      wv_raw, wv_scaled,
      xv_raw, xv_scaled,
      msv_raw, msv_scaled,
      wsv_raw, wsv_scaled,
      xsv_raw, xsv_scaled,
      muv_raw, muv_scaled,
      wuv_raw, wuv_scaled,
      xuv_raw, xuv_scaled
    ) VALUES (
      ?, ?, ?, ?, ?,
      ${categoryValuePlaceholders}
    )`;

    for (const row of rows) {
      const raw = row?.raw || {};
      const scaled = row?.scaled || {};

      const teamName = String(row?.team_name || '').trim();
      const teamMember = String(row?.team_member || '').trim();

      if (!teamMember) {
        await connection.rollback();
        return res.status(400).json({ message: 'Each row must include team_member.' });
      }

      const values = [
        eventId,
        teamName,
        teamMember,
        toNullableNumber(raw.final_score),
        toNullableNumber(scaled.final_score)
      ];

      for (const category of fixedCategoryColumns) {
        values.push(toNullableNumber(raw[category]));
        values.push(toNullableNumber(scaled[category]));
      }

      await connection.query(insertSql, values);
    }

    await connection.commit();

    return res.json({
      message: 'Transformed results saved successfully.',
      eventId,
      rowsSaved: rows.length
    });
  } catch (error) {
    await connection.rollback();
    return res.status(500).json({ message: error.message });
  } finally {
    connection.release();
  }
});

export default router;
