import { Router } from 'express';
import pool from '../config/db.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
const fixedCategoryColumns = ['MJ', 'WJ', 'XJ', 'MO', 'WO', 'XO', 'MV', 'WV', 'XV', 'MSV', 'WSV', 'XSV', 'MUV', 'WUV', 'XUV'];

function normalizeCategory(value) {
  const normalized = String(value || '').trim().toUpperCase();
  return fixedCategoryColumns.includes(normalized) ? normalized : '';
}

function convertWildcardPatternToRegex(pattern) {
  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return escaped
    .replace(/\\\*/g, '.*')
    .replace(/\\\?/g, '.');
}

function buildRegexPattern(pattern) {
  const trimmed = String(pattern || '').trim();
  if (!trimmed) {
    return '';
  }

  try {
    // Ensure valid regex; if it succeeds, return original pattern
    new RegExp(trimmed);
    return trimmed;
  } catch {
    return convertWildcardPatternToRegex(trimmed);
  }
}

function serializeRow(row, index) {
  const originalPattern = String(row.pattern || '');
  const isRegex = Boolean(row.is_regex);
  return {
    id: row.id,
    pattern: originalPattern,
    regexPattern: isRegex ? buildRegexPattern(originalPattern) : '',
    mappedCategory: row.mapped_category,
    isRegex,
    priority: Number.isFinite(Number(row.priority)) ? Number(row.priority) : index + 1
  };
}

router.get('/', async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT id, pattern, mapped_category, is_regex, priority
       FROM category_mappings
       ORDER BY priority ASC, id ASC`
    );

    return res.json(rows.map((row, index) => serializeRow(row, index)));
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({ message: 'category_mappings table does not exist. Run backend/sql/init.sql.' });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.put('/', requireAuth, async (req, res) => {
  const mappingRows = Array.isArray(req.body?.mappings) ? req.body.mappings : [];
  const sanitized = [];

  try {
    mappingRows.forEach((row, index) => {
      const pattern = String(row?.pattern || '').trim();
      const mappedCategory = normalizeCategory(row?.mappedCategory || row?.mapped_category);
      const isRegex = Boolean(row?.isRegex ?? row?.is_regex);
      const priorityValue = Number(row?.priority);
      const priority = Number.isFinite(priorityValue) ? priorityValue : index + 1;
      const regexPattern = isRegex ? buildRegexPattern(pattern) : '';

      if (!pattern) {
        throw new Error(`Row ${index + 1}: pattern is required.`);
      }

      if (!mappedCategory) {
        throw new Error(`Row ${index + 1}: mapped category is invalid.`);
      }

      if (isRegex) {
        try {
          // Validate regex syntax (after wildcard expansion if needed)
          new RegExp(regexPattern);
        } catch {
          throw new Error(`Row ${index + 1}: invalid regular expression.`);
        }
      }

      sanitized.push({ pattern, mappedCategory, isRegex: isRegex ? 1 : 0, priority });
    });
  } catch (validationError) {
    return res.status(400).json({ message: validationError.message });
  }

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();
    await connection.query('DELETE FROM category_mappings');

    if (sanitized.length > 0) {
      const insertSql = 'INSERT INTO category_mappings (pattern, mapped_category, is_regex, priority) VALUES (?, ?, ?, ?)';

      for (const row of sanitized) {
        await connection.query(insertSql, [row.pattern, row.mappedCategory, row.isRegex, row.priority]);
      }
    }

    await connection.commit();

    const [rows] = await connection.query(
      `SELECT id, pattern, mapped_category, is_regex, priority
       FROM category_mappings
       ORDER BY priority ASC, id ASC`
    );

    return res.json({
      message: 'Category mappings saved successfully.',
      mappings: rows.map((row, index) => serializeRow(row, index))
    });
  } catch (error) {
    await connection.rollback();

    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({ message: 'category_mappings table does not exist. Run backend/sql/init.sql.' });
    }

    return res.status(500).json({ message: error.message });
  } finally {
    connection.release();
  }
});

export default router;
