(() => {
  "use strict";

  const visualEditor = document.querySelector("#visual-editor");
  const writeArea = document.querySelector("#write");
  const sourceView = document.querySelector("#source-view");
  const sourceEditor = document.querySelector("#source-editor");
  const contextMenu = document.querySelector("#table-context-menu");
  const searchPanel = document.querySelector("#search-panel");
  const findInput = document.querySelector("#find-input");
  const replaceRow = document.querySelector("#replace-row");
  const replaceInput = document.querySelector("#replace-input");
  const searchStatus = document.querySelector("#search-status");
  const colorPalette = document.querySelector("#color-value-palette");
  const colorPaletteTitle = document.querySelector("#color-palette-title");
  const colorPaletteStops = document.querySelector("#color-palette-stops");
  const colorValueMetadata = new WeakMap();

  let blocks = parseMarkdown("");
  let sourceMode = false;
  let selectedTableIndex = null;
  let contextTarget = null;
  let undoStack = [];
  let redoStack = [];
  let lastHistoryGroup = null;
  let lastHistoryTime = 0;
  let lastVisualPosition = null;
  let searchMatches = [];
  let searchIndex = -1;
  let activeColorToken = null;
  let paletteHistoryStarted = false;

  function normalizeNewlines(value) {
    return value.replace(/\r\n?/g, "\n");
  }

  function decodeCell(value) {
    return value.trim().replace(/<br\s*\/?>/gi, "\n");
  }

  function rowCells(line) {
    const trimmed = line.trim();
    if (!trimmed || !hasUnescapedPipe(trimmed)) {
      return null;
    }

    let value = trimmed;
    if (value.startsWith("|")) {
      value = value.slice(1);
    }
    if (endsWithUnescapedPipe(value)) {
      value = value.slice(0, -1);
    }

    const cells = [];
    let cell = "";
    let escaped = false;

    for (const character of value) {
      if (escaped) {
        if (character === "|") {
          cell += "|";
        } else {
          cell += `\\${character}`;
        }
        escaped = false;
        continue;
      }

      if (character === "\\") {
        escaped = true;
      } else if (character === "|") {
        cells.push(decodeCell(cell));
        cell = "";
      } else {
        cell += character;
      }
    }

    if (escaped) {
      cell += "\\";
    }
    cells.push(decodeCell(cell));
    return cells;
  }

  function hasUnescapedPipe(value) {
    let escaped = false;
    for (const character of value) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === "|") {
        return true;
      }
    }
    return false;
  }

  function endsWithUnescapedPipe(value) {
    if (!value.endsWith("|")) {
      return false;
    }
    let backslashes = 0;
    for (let index = value.length - 2; index >= 0 && value[index] === "\\"; index -= 1) {
      backslashes += 1;
    }
    return backslashes % 2 === 0;
  }

  function alignmentFromDelimiter(value) {
    const delimiter = value.trim();
    if (!/^:?-{3,}:?$/.test(delimiter)) {
      return null;
    }
    const left = delimiter.startsWith(":");
    const right = delimiter.endsWith(":");
    if (left && right) return "center";
    if (right) return "right";
    if (left) return "left";
    return "default";
  }

  function tableAt(lines, start) {
    if (start + 1 >= lines.length) {
      return null;
    }

    const header = rowCells(lines[start]);
    const delimiterCells = rowCells(lines[start + 1]);
    if (!header || !delimiterCells || header.length !== delimiterCells.length) {
      return null;
    }

    const align = delimiterCells.map(alignmentFromDelimiter);
    if (align.some((value) => value === null)) {
      return null;
    }

    const rows = [];
    let end = start + 2;
    while (end < lines.length) {
      const cells = rowCells(lines[end]);
      if (!cells) break;
      rows.push(normalizeCellCount(cells, header.length));
      end += 1;
    }

    if (rows.length === 0) {
      rows.push(Array(header.length).fill(""));
    }

    return {
      block: {
        type: "table",
        header,
        align,
        rows,
      },
      end,
    };
  }

  function normalizeCellCount(cells, count) {
    const normalized = cells.slice(0, count);
    while (normalized.length < count) {
      normalized.push("");
    }
    return normalized;
  }

  function parseMarkdown(markdown) {
    const lines = normalizeNewlines(markdown).split("\n");
    const parsed = [];
    let textLines = [];

    const flushText = () => {
      if (textLines.length > 0) {
        parsed.push({ type: "text", lines: textLines });
        textLines = [];
      }
    };

    for (let index = 0; index < lines.length; ) {
      const table = tableAt(lines, index);
      if (table) {
        flushText();
        parsed.push(table.block);
        index = table.end;
      } else {
        textLines.push(lines[index]);
        index += 1;
      }
    }
    flushText();

    return parsed.length > 0 ? parsed : [{ type: "text", lines: [""] }];
  }

  function escapeCell(value) {
    return value.replace(/\|/g, "\\|").replace(/\n/g, "<br>");
  }

  function delimiterFor(alignment) {
    if (alignment === "left") return ":---";
    if (alignment === "right") return "---:";
    if (alignment === "center") return ":---:";
    return "---";
  }

  function serializeTable(table) {
    const line = (cells) => `| ${cells.map(escapeCell).join(" | ")} |`;
    return [
      line(table.header),
      line(table.align.map(delimiterFor)),
      ...table.rows.map(line),
    ];
  }

  function serializeBlocks() {
    const lines = [];
    for (const block of blocks) {
      lines.push(...(block.type === "table" ? serializeTable(block) : block.lines));
    }
    return lines.join("\n");
  }

  function parseExtendedColorAt(value, start) {
    const position = String.raw`(?:100(?:\.0+)?|\d{1,2}(?:\.\d+)?)`;
    const field = String.raw`${position}\s*:\s*#[0-9A-Fa-f]{6}`;
    const expression = new RegExp(String.raw`^([gGmM])\(\s*(${field}(?:\s*,\s*${field})*)\s*\)`);
    const match = expression.exec(value.slice(start));
    if (!match) return null;

    const raw = match[0];
    const stops = [];
    const stopExpression = new RegExp(
      String.raw`(${position})\s*:\s*(#[0-9A-Fa-f]{6})`,
      "g",
    );
    let stopMatch;
    while ((stopMatch = stopExpression.exec(raw))) {
      const colorOffset = stopMatch.index + stopMatch[0].lastIndexOf("#");
      stops.push({
        position: Number(stopMatch[1]),
        color: stopMatch[2].toUpperCase(),
        positionStart: stopMatch.index,
        positionEnd: stopMatch.index + stopMatch[1].length,
        colorStart: colorOffset,
        colorEnd: colorOffset + stopMatch[2].length,
      });
    }

    return {
      mode: match[1].toLowerCase() === "g" ? "gradient" : "millefeuille",
      start,
      end: start + raw.length,
      raw,
      stops,
    };
  }

  function colorValuesInText(value) {
    const values = [];
    let index = 0;
    while (index < value.length) {
      if (/[gGmM]/.test(value[index])) {
        const extended = parseExtendedColorAt(value, index);
        if (extended) {
          values.push(extended);
          index = extended.end;
          continue;
        }
      }

      if (value[index] === "#") {
        const remainder = value.slice(index);
        const pair = /^(#[0-9A-Fa-f]{6})\/(#[0-9A-Fa-f]{6})(?![0-9A-Fa-f])/.exec(remainder);
        if (pair) {
          values.push({
            mode: "gradient",
            start: index,
            end: index + pair[0].length,
            raw: pair[0],
            stops: [
              { position: 0, color: pair[1].toUpperCase(), colorStart: 0, colorEnd: 7 },
              { position: 100, color: pair[2].toUpperCase(), colorStart: 8, colorEnd: 15 },
            ],
          });
          index += pair[0].length;
          continue;
        }

        const solid = /^#[0-9A-Fa-f]{6}(?![0-9A-Fa-f])/.exec(remainder);
        if (solid) {
          values.push({
            mode: "solid",
            start: index,
            end: index + solid[0].length,
            raw: solid[0],
            stops: [{
              position: 0,
              color: solid[0].toUpperCase(),
              colorStart: 0,
              colorEnd: solid[0].length,
            }],
          });
          index += solid[0].length;
          continue;
        }
      }
      index += 1;
    }
    return values;
  }

  function normalizedColorStops(value) {
    return value.stops
      .map((stop, index) => ({ ...stop, sourceIndex: index }))
      .sort((left, right) => left.position - right.position || left.sourceIndex - right.sourceIndex);
  }

  function previewBackground(value) {
    const stops = normalizedColorStops(value);
    if (stops.length === 0) return "transparent";
    if (value.mode === "solid" || stops.length === 1) return stops[0].color;
    if (value.mode === "gradient") {
      return `linear-gradient(to bottom, ${stops
        .map((stop) => `${stop.color} ${stop.position}%`)
        .join(", ")})`;
    }

    const bands = [];
    stops.forEach((stop, index) => {
      const end = stops[index + 1]?.position ?? 100;
      bands.push(`${stop.color} ${stop.position}%`, `${stop.color} ${end}%`);
    });
    return `linear-gradient(to bottom, ${bands.join(", ")})`;
  }

  function appendColorValueText(container, value) {
    let offset = 0;
    value.stops.forEach((stop, stopIndex) => {
      if (Number.isInteger(stop.positionStart)) {
        if (stop.positionStart > offset) {
          container.append(document.createTextNode(value.raw.slice(offset, stop.positionStart)));
        }
        const position = document.createElement("span");
        position.className = "color-position-code";
        position.dataset.stopIndex = String(stopIndex);
        position.textContent = value.raw.slice(stop.positionStart, stop.positionEnd);
        container.append(position);
        offset = stop.positionEnd;
      }
      if (stop.colorStart > offset) {
        container.append(document.createTextNode(value.raw.slice(offset, stop.colorStart)));
      }
      const code = document.createElement("span");
      code.className = "color-code";
      code.dataset.stopIndex = String(stopIndex);
      code.textContent = value.raw.slice(stop.colorStart, stop.colorEnd);
      container.append(code);
      offset = stop.colorEnd;
    });
    if (offset < value.raw.length) {
      container.append(document.createTextNode(value.raw.slice(offset)));
    }
  }

  function createSolidColorToken(value) {
    const token = document.createElement("span");
    token.className = "color-token";

    const swatch = document.createElement("input");
    swatch.className = "color-swatch";
    swatch.type = "color";
    swatch.value = value.stops[0].color;
    swatch.tabIndex = -1;
    swatch.contentEditable = "false";
    swatch.setAttribute("aria-label", `选择颜色 ${value.stops[0].color}`);

    const code = document.createElement("span");
    code.className = "color-code";
    code.textContent = value.raw;
    token.append(swatch, code);
    return token;
  }

  function createCompoundColorToken(value) {
    const token = document.createElement("span");
    token.className = `color-expression color-expression-${value.mode}`;

    const swatch = document.createElement("button");
    swatch.className = "color-expression-swatch";
    swatch.type = "button";
    swatch.tabIndex = -1;
    swatch.contentEditable = "false";
    swatch.style.background = previewBackground(value);
    swatch.setAttribute(
      "aria-label",
      value.mode === "gradient" ? "编辑渐变颜色" : "编辑ミルフィーユ颜色",
    );
    token.append(swatch);
    appendColorValueText(token, value);
    colorValueMetadata.set(token, value);
    return token;
  }

  function renderCellContent(editor, value) {
    const fragment = document.createDocumentFragment();
    const colorValues = colorValuesInText(value);
    let offset = 0;
    colorValues.forEach((colorValue) => {
      if (colorValue.start > offset) {
        fragment.append(document.createTextNode(value.slice(offset, colorValue.start)));
      }
      fragment.append(
        colorValue.mode === "solid"
          ? createSolidColorToken(colorValue)
          : createCompoundColorToken(colorValue),
      );
      offset = colorValue.end;
    });
    if (offset < value.length) {
      fragment.append(document.createTextNode(value.slice(offset)));
    }
    editor.replaceChildren(fragment);
  }

  function currentMarkdown() {
    return sourceMode ? sourceEditor.value : serializeBlocks();
  }

  function checkpoint(group = null) {
    const markdown = currentMarkdown();
    const now = Date.now();
    if (group && group === lastHistoryGroup && now - lastHistoryTime < 900) {
      lastHistoryTime = now;
      redoStack = [];
      return;
    }
    if (undoStack[undoStack.length - 1] !== markdown) {
      undoStack.push(markdown);
    }
    redoStack = [];
    lastHistoryGroup = group;
    lastHistoryTime = now;
  }

  function resetHistoryGroup() {
    lastHistoryGroup = null;
    lastHistoryTime = 0;
  }

  function restoreMarkdown(markdown) {
    clearTableSelection();
    hideContextMenu();
    if (sourceMode) {
      sourceEditor.value = markdown;
    } else {
      blocks = parseMarkdown(markdown);
      renderVisual();
    }
    if (!searchPanel.hidden) refreshSearch();
  }

  function undoDocument() {
    if (undoStack.length === 0) return;
    resetHistoryGroup();
    const current = currentMarkdown();
    const previous = undoStack.pop();
    if (redoStack[redoStack.length - 1] !== current) {
      redoStack.push(current);
    }
    restoreMarkdown(previous);
  }

  function redoDocument() {
    if (redoStack.length === 0) return;
    resetHistoryGroup();
    const current = currentMarkdown();
    const next = redoStack.pop();
    if (undoStack[undoStack.length - 1] !== current) {
      undoStack.push(current);
    }
    restoreMarkdown(next);
  }

  function createCell(tagName, value, blockIndex, rowIndex, columnIndex) {
    const cell = document.createElement(tagName);

    const editor = document.createElement("span");
    editor.className = "cell-editor";
    editor.contentEditable = "plaintext-only";
    editor.spellcheck = false;
    editor.dataset.blockIndex = String(blockIndex);
    editor.dataset.rowIndex = String(rowIndex);
    editor.dataset.columnIndex = String(columnIndex);
    renderCellContent(editor, value);
    cell.append(editor);
    return cell;
  }

  function createRowControls(blockIndex, rowIndex) {
    const controls = document.createElement("span");
    controls.className = "row-controls";
    controls.contentEditable = "false";

    const add = document.createElement("button");
    add.className = "row-control";
    add.type = "button";
    add.dataset.action = "add-row";
    add.dataset.blockIndex = String(blockIndex);
    add.dataset.rowIndex = String(rowIndex);
    add.title = "在下方添加行 (Ctrl+Enter)";
    add.setAttribute("aria-label", "在下方添加行");
    add.textContent = "+";

    const remove = document.createElement("button");
    remove.className = "row-control";
    remove.type = "button";
    remove.dataset.action = "delete-row";
    remove.dataset.blockIndex = String(blockIndex);
    remove.dataset.rowIndex = String(rowIndex);
    remove.title = "删除此行 (Ctrl+Shift+Backspace)";
    remove.setAttribute("aria-label", "删除此行");
    remove.textContent = "−";

    controls.append(add, remove);
    return controls;
  }

  function createTable(block, blockIndex) {
    const figure = document.createElement("figure");
    figure.className = "table-figure";
    figure.dataset.blockIndex = String(blockIndex);
    figure.tabIndex = -1;

    const selector = document.createElement("button");
    selector.className = "table-selector";
    selector.type = "button";
    selector.dataset.action = "select-table";
    selector.dataset.blockIndex = String(blockIndex);
    selector.title = "选择整个表格 (Esc)";
    selector.setAttribute("aria-label", "选择整个表格");
    selector.textContent = "▦";

    const table = document.createElement("table");
    table.className = "md-table";
    table.dataset.blockIndex = String(blockIndex);

    const head = document.createElement("thead");
    const headerRow = document.createElement("tr");
    block.header.forEach((value, columnIndex) => {
      headerRow.append(createCell("th", value, blockIndex, -1, columnIndex));
    });
    head.append(headerRow);

    const body = document.createElement("tbody");
    block.rows.forEach((row, rowIndex) => {
      const tableRow = document.createElement("tr");
      row.forEach((value, columnIndex) => {
        const cell = createCell("td", value, blockIndex, rowIndex, columnIndex);
        if (columnIndex === 0) {
          cell.append(createRowControls(blockIndex, rowIndex));
        }
        tableRow.append(cell);
      });
      body.append(tableRow);
    });

    table.append(head, body);
    figure.append(selector, table);
    return figure;
  }

  function renderVisual(focus = null) {
    closeColorPalette();
    const fragment = document.createDocumentFragment();

    blocks.forEach((block, blockIndex) => {
      if (block.type === "table") {
        fragment.append(createTable(block, blockIndex));
        return;
      }

      const raw = document.createElement("div");
      raw.className = "raw-block";
      raw.contentEditable = "plaintext-only";
      raw.spellcheck = false;
      raw.dataset.blockIndex = String(blockIndex);
      raw.dataset.placeholder = "粘贴 yuukilyrics 配色表以开始编辑";
      raw.setAttribute("aria-label", "粘贴 yuukilyrics 配色表以开始编辑");
      raw.textContent = block.lines.join("\n");
      fragment.append(raw);
    });

    visualEditor.replaceChildren(fragment);
    if (focus) {
      focusCell(
        focus.blockIndex,
        focus.rowIndex,
        focus.columnIndex,
        focus.atEnd,
        focus.offset,
      );
    }
  }

  function focusCell(blockIndex, rowIndex, columnIndex, atEnd = false, offset = null) {
    const selector = [
      `.cell-editor[data-block-index="${blockIndex}"]`,
      `[data-row-index="${rowIndex}"]`,
      `[data-column-index="${columnIndex}"]`,
    ].join("");
    const cell = visualEditor.querySelector(selector);
    if (!cell) return;
    cell.focus();

    const selection = window.getSelection();
    let range = Number.isInteger(offset)
      ? rangeForTextOffsets(cell, offset, offset)
      : null;
    if (!range) {
      range = document.createRange();
      range.selectNodeContents(cell);
      range.collapse(!atEnd);
    }
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function caretOffsetInCell(cell) {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || !selection.isCollapsed) return null;
    const activeRange = selection.getRangeAt(0);
    const container =
      activeRange.endContainer.nodeType === Node.TEXT_NODE
        ? activeRange.endContainer.parentElement
        : activeRange.endContainer;
    if (!container || (container !== cell && !cell.contains(container))) return null;

    const beforeCaret = activeRange.cloneRange();
    beforeCaret.selectNodeContents(cell);
    beforeCaret.setEnd(activeRange.endContainer, activeRange.endOffset);
    return beforeCaret.toString().length;
  }

  function textOffsetFromPoint(cell, x, y) {
    let pointRange = document.caretRangeFromPoint?.(x, y) ?? null;
    if (!pointRange && document.caretPositionFromPoint) {
      const position = document.caretPositionFromPoint(x, y);
      if (position) {
        pointRange = document.createRange();
        pointRange.setStart(position.offsetNode, position.offset);
        pointRange.collapse(true);
      }
    }
    if (!pointRange) return null;

    const container =
      pointRange.startContainer.nodeType === Node.TEXT_NODE
        ? pointRange.startContainer.parentElement
        : pointRange.startContainer;
    if (!container || (container !== cell && !cell.contains(container))) return null;

    const beforePoint = pointRange.cloneRange();
    beforePoint.selectNodeContents(cell);
    beforePoint.setEnd(pointRange.startContainer, pointRange.startOffset);
    return beforePoint.toString().length;
  }

  function selectAsciiTokenAtPoint(cell, x, y) {
    const offset = textOffsetFromPoint(cell, x, y);
    if (offset === null) return false;

    const text = cell.textContent;
    const expression = /[A-Za-z0-9_]+/g;
    let match;
    while ((match = expression.exec(text))) {
      const start = match.index;
      const end = start + match[0].length;
      if ((offset >= start && offset < end) || (offset > start && offset - 1 < end)) {
        const range = rangeForTextOffsets(cell, start, end);
        if (!range) return false;
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        return true;
      }
    }
    return false;
  }

  function moveHorizontalCell(position, table, backward) {
    const columns = table.header.length;
    const current = (position.rowIndex + 1) * columns + position.columnIndex;
    const target = current + (backward ? -1 : 1);
    const total = (table.rows.length + 1) * columns;
    if (target < 0 || target >= total) return false;

    const logicalRow = Math.floor(target / columns);
    focusCell(position.blockIndex, logicalRow - 1, target % columns, backward);
    return true;
  }

  function clearTableSelection() {
    selectedTableIndex = null;
    visualEditor.querySelectorAll(".table-selected").forEach((figure) => {
      figure.classList.remove("table-selected");
      figure.removeAttribute("aria-selected");
    });
  }

  function selectTable(blockIndex) {
    clearTableSelection();
    const table = blocks[blockIndex];
    if (!table || table.type !== "table") return;

    selectedTableIndex = blockIndex;
    const figure = visualEditor.querySelector(
      `.table-figure[data-block-index="${blockIndex}"]`,
    );
    if (!figure) return;
    figure.classList.add("table-selected");
    figure.setAttribute("aria-selected", "true");
    figure.focus();
    window.getSelection()?.removeAllRanges();
  }

  function mergeAdjacentTextBlocks() {
    for (let index = blocks.length - 2; index >= 0; index -= 1) {
      if (blocks[index].type === "text" && blocks[index + 1].type === "text") {
        blocks[index].lines.push(...blocks[index + 1].lines);
        blocks.splice(index + 1, 1);
      }
    }
  }

  function deleteTable(blockIndex) {
    const table = blocks[blockIndex];
    if (!table || table.type !== "table") return;

    checkpoint();
    blocks.splice(blockIndex, 1);
    mergeAdjacentTextBlocks();
    if (blocks.length === 0) {
      blocks = [{ type: "text", lines: [""] }];
    }
    selectedTableIndex = null;
    renderVisual();
    visualEditor.querySelector(".cell-editor, .raw-block")?.focus();
  }

  function hideContextMenu() {
    contextMenu.hidden = true;
    contextTarget = null;
  }

  function showContextMenu(event, figure, cell) {
    if (cell) {
      clearTableSelection();
    }
    const blockIndex = Number(figure.dataset.blockIndex);
    const rowIndex = cell ? Number(cell.dataset.rowIndex) : -1;
    const columnIndex = cell ? Number(cell.dataset.columnIndex) : 0;
    let selectionRange = null;
    const selection = window.getSelection();
    if (cell && selection && selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      const container =
        range.commonAncestorContainer.nodeType === Node.TEXT_NODE
          ? range.commonAncestorContainer.parentElement
          : range.commonAncestorContainer;
      if (container && (container === cell || cell.contains(container))) {
        selectionRange = range.cloneRange();
      }
    }
    if (cell && !selectionRange) {
      selectionRange = document.createRange();
      selectionRange.selectNodeContents(cell);
      selectionRange.collapse(false);
    }

    contextTarget = { blockIndex, rowIndex, columnIndex, cell, selectionRange };

    const rowActionsDisabled = rowIndex < 0;
    for (const action of ["add-row-before", "add-row-after", "delete-row"]) {
      contextMenu.querySelector(`[data-action="${action}"]`).disabled = rowActionsDisabled;
    }
    const hasTextSelection = Boolean(selectionRange && !selectionRange.collapsed);
    contextMenu.querySelector('[data-action="undo"]').disabled = undoStack.length === 0;
    contextMenu.querySelector('[data-action="redo"]').disabled = redoStack.length === 0;
    contextMenu.querySelector('[data-action="cut-text"]').disabled = !hasTextSelection;
    contextMenu.querySelector('[data-action="copy-text"]').disabled = !hasTextSelection;
    contextMenu.querySelector('[data-action="paste-text"]').disabled = !cell;
    contextMenu.querySelector('[data-action="select-all-text"]').disabled = !cell;
    contextMenu.querySelector('[data-action="insert-gradient"]').disabled = !cell;
    contextMenu.querySelector('[data-action="insert-millefeuille"]').disabled = !cell;

    contextMenu.hidden = false;
    contextMenu.style.left = `${event.clientX}px`;
    contextMenu.style.top = `${event.clientY}px`;

    const bounds = contextMenu.getBoundingClientRect();
    const left = Math.max(4, Math.min(event.clientX, window.innerWidth - bounds.width - 4));
    const top = Math.max(4, Math.min(event.clientY, window.innerHeight - bounds.height - 4));
    contextMenu.style.left = `${left}px`;
    contextMenu.style.top = `${top}px`;
  }

  async function writeClipboardText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      const fallback = document.createElement("textarea");
      fallback.value = text;
      fallback.setAttribute("readonly", "");
      fallback.style.position = "fixed";
      fallback.style.opacity = "0";
      document.body.append(fallback);
      fallback.select();
      document.execCommand("copy");
      fallback.remove();
    }
  }

  async function copyTableFromMenu(blockIndex) {
    const table = blocks[blockIndex];
    if (!table || table.type !== "table") return;
    const markdown = serializeTable(table).join("\n");
    selectTable(blockIndex);
    await writeClipboardText(markdown);
  }

  function restoreContextSelection(target) {
    if (!target.cell || !target.selectionRange) return false;
    target.cell.focus();
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(target.selectionRange);
    return true;
  }

  async function copyTextFromMenu(target, cut) {
    if (!target.selectionRange || target.selectionRange.collapsed) return;
    await writeClipboardText(target.selectionRange.toString());
    if (!restoreContextSelection(target) || !cut) return;
    checkpoint();
    const range = window.getSelection().getRangeAt(0);
    range.deleteContents();
    range.collapse(true);
    target.cell.dispatchEvent(
      new InputEvent("input", { bubbles: true, inputType: "deleteByCut" }),
    );
  }

  async function pasteTextFromMenu(target) {
    try {
      const text = await navigator.clipboard.readText();
      if (!restoreContextSelection(target)) return;
      checkpoint();
      insertPlainText(normalizeNewlines(text));
      target.cell.dispatchEvent(
        new InputEvent("input", { bubbles: true, inputType: "insertFromPaste" }),
      );
    } catch {
      restoreContextSelection(target);
    }
  }

  function selectAllTextFromMenu(target) {
    if (!target.cell) return;
    target.cell.focus();
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(target.cell);
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function insertColorTemplateFromMenu(target, template) {
    if (!restoreContextSelection(target)) return;
    checkpoint();
    insertPlainText(template);
    target.cell.dispatchEvent(
      new InputEvent("input", { bubbles: true, inputType: "insertText" }),
    );
  }

  function searchTargetsForDocument() {
    if (sourceMode) {
      return [{ kind: "source", value: sourceEditor.value }];
    }

    const targets = [];
    blocks.forEach((block, blockIndex) => {
      if (block.type === "text") {
        targets.push({ kind: "text", blockIndex, value: block.lines.join("\n") });
        return;
      }

      targets.push({
        kind: "cell",
        blockIndex,
        rowIndex: -1,
        values: block.header,
      });
      block.rows.forEach((row, rowIndex) => {
        targets.push({ kind: "cell", blockIndex, rowIndex, values: row });
      });
    });

    return targets.flatMap((target) => {
      if (target.kind !== "cell") return [target];
      return target.values.map((value, columnIndex) => ({
        kind: "cell",
        blockIndex: target.blockIndex,
        rowIndex: target.rowIndex,
        columnIndex,
        value,
      }));
    });
  }

  function collectSearchMatches(query) {
    if (!query) return [];
    const needle = query.toLocaleLowerCase();
    const matches = [];
    for (const target of searchTargetsForDocument()) {
      const haystack = target.value.toLocaleLowerCase();
      let start = 0;
      while ((start = haystack.indexOf(needle, start)) !== -1) {
        matches.push({ ...target, start, end: start + query.length });
        start += Math.max(query.length, 1);
      }
    }
    return matches;
  }

  function elementForSearchMatch(match) {
    if (match.kind === "text") {
      return visualEditor.querySelector(`.raw-block[data-block-index="${match.blockIndex}"]`);
    }
    if (match.kind !== "cell") return null;
    return visualEditor.querySelector(
      `.cell-editor[data-block-index="${match.blockIndex}"]` +
        `[data-row-index="${match.rowIndex}"]` +
        `[data-column-index="${match.columnIndex}"]`,
    );
  }

  function rangeForTextOffsets(element, start, end) {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    const range = document.createRange();
    let offset = 0;
    let startSet = false;
    let node;

    while ((node = walker.nextNode())) {
      const nextOffset = offset + node.data.length;
      if (!startSet && start <= nextOffset) {
        range.setStart(node, Math.max(0, start - offset));
        startSet = true;
      }
      if (startSet && end <= nextOffset) {
        range.setEnd(node, Math.max(0, end - offset));
        return range;
      }
      offset = nextOffset;
    }
    return null;
  }

  function clearSearchHighlights() {
    CSS.highlights?.delete("table-search-match");
    CSS.highlights?.delete("table-search-current");
  }

  function updateSearchHighlights() {
    clearSearchHighlights();
    if (sourceMode || !CSS.highlights || typeof Highlight === "undefined") return;

    const ranges = [];
    let currentRange = null;
    searchMatches.forEach((match, index) => {
      const element = elementForSearchMatch(match);
      if (!element) return;
      const range = rangeForTextOffsets(element, match.start, match.end);
      if (!range) return;
      ranges.push(range);
      if (index === searchIndex) {
        currentRange = range;
        element.scrollIntoView({ block: "center", inline: "nearest" });
      }
    });

    if (ranges.length) CSS.highlights.set("table-search-match", new Highlight(...ranges));
    if (currentRange) CSS.highlights.set("table-search-current", new Highlight(currentRange));
  }

  function showSearchMatch() {
    if (searchIndex < 0 || searchIndex >= searchMatches.length) return;
    const match = searchMatches[searchIndex];
    if (match.kind === "source") {
      sourceEditor.setSelectionRange(match.start, match.end);
      return;
    }
    updateSearchHighlights();
  }

  function refreshSearch(preferredIndex = 0) {
    clearSearchHighlights();
    searchMatches = collectSearchMatches(findInput.value);
    searchIndex = searchMatches.length
      ? Math.min(Math.max(preferredIndex, 0), searchMatches.length - 1)
      : -1;
    searchStatus.textContent = searchMatches.length ? `${searchIndex + 1}/${searchMatches.length}` : "0/0";
    showSearchMatch();
  }

  function moveSearch(delta) {
    if (searchMatches.length === 0) return;
    searchIndex = (searchIndex + delta + searchMatches.length) % searchMatches.length;
    searchStatus.textContent = `${searchIndex + 1}/${searchMatches.length}`;
    showSearchMatch();
  }

  function openSearch(replaceMode) {
    hideContextMenu();
    searchPanel.hidden = false;
    replaceRow.hidden = !replaceMode;
    findInput.focus();
    findInput.select();
    refreshSearch(searchIndex < 0 ? 0 : searchIndex);
  }

  function closeSearch() {
    searchPanel.hidden = true;
    searchMatches = [];
    searchIndex = -1;
    searchStatus.textContent = "0/0";
    clearSearchHighlights();
    window.getSelection()?.removeAllRanges();
    if (sourceMode) sourceEditor.focus();
    else visualEditor.querySelector(".cell-editor, .raw-block")?.focus();
  }

  function valueForMatch(match) {
    if (match.kind === "source") return sourceEditor.value;
    if (match.kind === "text") return blocks[match.blockIndex].lines.join("\n");
    const table = blocks[match.blockIndex];
    const row = match.rowIndex === -1 ? table.header : table.rows[match.rowIndex];
    return row[match.columnIndex];
  }

  function setValueForMatch(match, value) {
    if (match.kind === "source") {
      sourceEditor.value = value;
      return;
    }
    if (match.kind === "text") {
      blocks[match.blockIndex].lines = value.split("\n");
      return;
    }
    const table = blocks[match.blockIndex];
    const row = match.rowIndex === -1 ? table.header : table.rows[match.rowIndex];
    row[match.columnIndex] = value;
  }

  function replaceCurrentMatch() {
    if (searchIndex < 0 || searchIndex >= searchMatches.length) return;
    checkpoint();
    const match = searchMatches[searchIndex];
    const value = valueForMatch(match);
    setValueForMatch(
      match,
      value.slice(0, match.start) + replaceInput.value + value.slice(match.end),
    );
    if (!sourceMode) renderVisual();
    refreshSearch(searchIndex);
  }

  function replaceAllMatches() {
    const query = findInput.value;
    if (!query || searchMatches.length === 0) return;
    checkpoint();
    const expression = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
    for (const target of searchTargetsForDocument()) {
      if (!expression.test(target.value)) continue;
      expression.lastIndex = 0;
      setValueForMatch(target, target.value.replace(expression, () => replaceInput.value));
    }
    if (!sourceMode) renderVisual();
    refreshSearch(0);
  }

  function writeSelectedTableToClipboard(event) {
    if (sourceMode || selectedTableIndex === null) return false;
    const table = blocks[selectedTableIndex];
    if (!table || table.type !== "table") return false;
    event.clipboardData?.setData("text/plain", serializeTable(table).join("\n"));
    event.preventDefault();
    return true;
  }

  function cellPosition(element) {
    return {
      blockIndex: Number(element.dataset.blockIndex),
      rowIndex: Number(element.dataset.rowIndex),
      columnIndex: Number(element.dataset.columnIndex),
    };
  }

  function textFromEditable(element) {
    return normalizeNewlines(element.innerText);
  }

  function updateCell(element) {
    const position = cellPosition(element);
    const table = blocks[position.blockIndex];
    const row = position.rowIndex === -1 ? table.header : table.rows[position.rowIndex];
    row[position.columnIndex] = textFromEditable(element);
  }

  function valueForCell(element) {
    const position = cellPosition(element);
    const table = blocks[position.blockIndex];
    if (!table || table.type !== "table") return null;
    const row = position.rowIndex === -1 ? table.header : table.rows[position.rowIndex];
    return row?.[position.columnIndex] ?? null;
  }

  function refreshCellDecoration(element, preserveCaret = false) {
    const value = valueForCell(element);
    if (value === null) return;
    const position = cellPosition(element);
    const offset = preserveCaret ? caretOffsetInCell(element) : null;
    renderCellContent(element, value);
    if (preserveCaret && offset !== null) {
      focusCell(
        position.blockIndex,
        position.rowIndex,
        position.columnIndex,
        false,
        offset,
      );
    }
  }

  function applySwatchColor(swatch) {
    const cell = swatch.closest(".cell-editor");
    const code = swatch.closest(".color-token")?.querySelector(".color-code");
    if (!cell || !code) return false;

    const nextColor = swatch.value.toUpperCase();
    if (code.textContent.toUpperCase() === nextColor) return false;
    if (!swatch.dataset.historyStarted) {
      checkpoint();
      swatch.dataset.historyStarted = "true";
    }

    code.textContent = nextColor;
    swatch.setAttribute("aria-label", `选择颜色 ${nextColor}`);
    updateCell(cell);
    if (!searchPanel.hidden) refreshSearch(searchIndex < 0 ? 0 : searchIndex);
    return true;
  }

  function formatStopPosition(position) {
    if (Number.isInteger(position)) return String(position);
    return position.toFixed(3).replace(/\.?0+$/, "");
  }

  function serializeCompoundColorValue(value) {
    const prefix = value.mode === "gradient" ? "g" : "m";
    return `${prefix}(${normalizedColorStops(value)
      .map((stop) => `${formatStopPosition(stop.position)}:${stop.color}`)
      .join(",")})`;
  }

  function closeColorPalette() {
    colorPalette.hidden = true;
    colorPaletteStops.replaceChildren();
    activeColorToken = null;
    paletteHistoryStarted = false;
  }

  function openColorPalette(token, anchor, preserveHistory = false) {
    const value = colorValueMetadata.get(token);
    if (!value) return;

    activeColorToken = token;
    if (!preserveHistory) paletteHistoryStarted = false;
    colorPaletteTitle.textContent = value.mode === "gradient" ? "渐变" : "ミルフィーユ";

    const fragment = document.createDocumentFragment();
    normalizedColorStops(value).forEach((stop) => {
      const row = document.createElement("div");
      row.className = "color-palette-stop";

      const position = document.createElement("span");
      position.className = "color-palette-position";

      const positionInput = document.createElement("input");
      positionInput.type = "number";
      positionInput.min = "0";
      positionInput.max = "100";
      positionInput.step = "any";
      positionInput.inputMode = "decimal";
      positionInput.value = formatStopPosition(stop.position);
      positionInput.dataset.stopIndex = String(stop.sourceIndex);
      positionInput.disabled = !Number.isInteger(stop.positionStart);
      positionInput.setAttribute("aria-label", "色标位置百分比");

      const percent = document.createElement("span");
      percent.textContent = "%";
      position.append(positionInput, percent);

      const picker = document.createElement("input");
      picker.type = "color";
      picker.value = stop.color;
      picker.dataset.stopIndex = String(stop.sourceIndex);
      picker.setAttribute("aria-label", `${formatStopPosition(stop.position)}% 的颜色`);

      const code = document.createElement("span");
      code.className = "color-palette-code";
      code.dataset.stopIndex = String(stop.sourceIndex);
      code.textContent = stop.color;

      const actions = document.createElement("span");
      actions.className = "color-palette-actions";

      const add = document.createElement("button");
      add.type = "button";
      add.dataset.action = "add-color-stop";
      add.dataset.stopIndex = String(stop.sourceIndex);
      add.title = "在此色标后添加";
      add.setAttribute("aria-label", "在此色标后添加");
      add.textContent = "+";

      const remove = document.createElement("button");
      remove.type = "button";
      remove.dataset.action = "delete-color-stop";
      remove.dataset.stopIndex = String(stop.sourceIndex);
      remove.title = "删除此色标";
      remove.setAttribute("aria-label", "删除此色标");
      remove.textContent = "−";
      remove.disabled = value.stops.length <= 2;

      actions.append(add, remove);
      row.append(position, picker, code, actions);
      fragment.append(row);
    });
    colorPaletteStops.replaceChildren(fragment);
    colorPalette.hidden = false;

    const anchorBounds = anchor.getBoundingClientRect();
    const paletteBounds = colorPalette.getBoundingClientRect();
    const left = Math.max(
      6,
      Math.min(anchorBounds.left, window.innerWidth - paletteBounds.width - 6),
    );
    const preferredTop = anchorBounds.bottom + 6;
    const top = preferredTop + paletteBounds.height <= window.innerHeight - 6
      ? preferredTop
      : Math.max(6, anchorBounds.top - paletteBounds.height - 6);
    colorPalette.style.left = `${left}px`;
    colorPalette.style.top = `${top}px`;
  }

  function applyCompoundStopColor(stopIndex, nextValue) {
    const token = activeColorToken;
    const value = token ? colorValueMetadata.get(token) : null;
    const cell = token?.closest(".cell-editor");
    const stop = value?.stops[stopIndex];
    if (!token || !value || !cell || !stop) return;

    const nextColor = nextValue.toUpperCase();
    if (stop.color === nextColor) return;
    if (!paletteHistoryStarted) {
      checkpoint();
      paletteHistoryStarted = true;
    }

    stop.color = nextColor;
    token.querySelector(`.color-code[data-stop-index="${stopIndex}"]`).textContent = nextColor;
    token.querySelector(".color-expression-swatch").style.background = previewBackground(value);
    const paletteCode = colorPalette.querySelector(
      `.color-palette-code[data-stop-index="${stopIndex}"]`,
    );
    if (paletteCode) paletteCode.textContent = nextColor;
    updateCell(cell);
    if (!searchPanel.hidden) refreshSearch(searchIndex < 0 ? 0 : searchIndex);
  }

  function applyCompoundStopPosition(stopIndex, nextValue) {
    const token = activeColorToken;
    const value = token ? colorValueMetadata.get(token) : null;
    const cell = token?.closest(".cell-editor");
    const stop = value?.stops[stopIndex];
    const parsedPosition = Number(nextValue);
    const nextPosition = Number(formatStopPosition(parsedPosition));
    if (
      !token ||
      !value ||
      !cell ||
      !stop ||
      !Number.isFinite(parsedPosition) ||
      parsedPosition < 0 ||
      parsedPosition > 100 ||
      stop.position === nextPosition
    ) {
      return false;
    }
    if (!paletteHistoryStarted) {
      checkpoint();
      paletteHistoryStarted = true;
    }

    stop.position = nextPosition;
    const positionCode = token.querySelector(
      `.color-position-code[data-stop-index="${stopIndex}"]`,
    );
    if (positionCode) positionCode.textContent = formatStopPosition(nextPosition);
    token.querySelector(".color-expression-swatch").style.background = previewBackground(value);
    updateCell(cell);
    if (!searchPanel.hidden) refreshSearch(searchIndex < 0 ? 0 : searchIndex);
    return true;
  }

  function rebuildActiveCompoundColor() {
    const token = activeColorToken;
    const value = token ? colorValueMetadata.get(token) : null;
    const cell = token?.closest(".cell-editor");
    if (!token || !value || !cell) return;

    const raw = serializeCompoundColorValue(value);
    const parsed = parseExtendedColorAt(raw, 0);
    if (!parsed) return;
    const nextToken = createCompoundColorToken(parsed);
    token.replaceWith(nextToken);
    updateCell(cell);
    openColorPalette(
      nextToken,
      nextToken.querySelector(".color-expression-swatch"),
      true,
    );
    if (!searchPanel.hidden) refreshSearch(searchIndex < 0 ? 0 : searchIndex);
  }

  function addCompoundColorStop(stopIndex) {
    const value = activeColorToken ? colorValueMetadata.get(activeColorToken) : null;
    const selected = value?.stops[stopIndex];
    if (!value || !selected) return;
    if (!paletteHistoryStarted) {
      checkpoint();
      paletteHistoryStarted = true;
    }

    const ordered = normalizedColorStops(value);
    const orderedIndex = ordered.findIndex((stop) => stop.sourceIndex === stopIndex);
    const nextPosition = ordered[orderedIndex + 1]?.position ?? 100;
    value.stops.push({
      position: (selected.position + nextPosition) / 2,
      color: selected.color,
    });
    rebuildActiveCompoundColor();
  }

  function deleteCompoundColorStop(stopIndex) {
    const value = activeColorToken ? colorValueMetadata.get(activeColorToken) : null;
    if (!value || value.stops.length <= 2 || !value.stops[stopIndex]) return;
    if (!paletteHistoryStarted) {
      checkpoint();
      paletteHistoryStarted = true;
    }

    value.stops.splice(stopIndex, 1);
    rebuildActiveCompoundColor();
  }

  function addRow(blockIndex, rowIndex, focusColumn = 0) {
    const table = blocks[blockIndex];
    if (!table || table.type !== "table") return;
    checkpoint();
    const insertionIndex = Math.max(0, rowIndex + 1);
    table.rows.splice(insertionIndex, 0, Array(table.header.length).fill(""));
    renderVisual({ blockIndex, rowIndex: insertionIndex, columnIndex: focusColumn });
  }

  function deleteRow(blockIndex, rowIndex, focusColumn = 0) {
    const table = blocks[blockIndex];
    if (!table || table.type !== "table" || rowIndex < 0) return;

    checkpoint();
    if (table.rows.length === 1) {
      table.rows[0] = Array(table.header.length).fill("");
      renderVisual({ blockIndex, rowIndex: 0, columnIndex: focusColumn });
      return;
    }

    table.rows.splice(rowIndex, 1);
    const nextRow = Math.min(rowIndex, table.rows.length - 1);
    renderVisual({ blockIndex, rowIndex: nextRow, columnIndex: focusColumn });
  }

  function toggleSourceMode() {
    hideContextMenu();
    closeColorPalette();
    sourceMode = !sourceMode;
    if (sourceMode) {
      const activeCell = document.activeElement?.closest?.(".cell-editor");
      if (activeCell) {
        lastVisualPosition = {
          ...cellPosition(activeCell),
          offset: caretOffsetInCell(activeCell),
        };
      }
      clearTableSelection();
      sourceEditor.value = serializeBlocks();
      writeArea.hidden = true;
      sourceView.hidden = false;
      sourceEditor.focus();
      sourceEditor.setSelectionRange(sourceEditor.value.length, sourceEditor.value.length);
    } else {
      blocks = parseMarkdown(sourceEditor.value);
      selectedTableIndex = null;
      sourceView.hidden = true;
      writeArea.hidden = false;
      renderVisual(lastVisualPosition);
      if (!document.activeElement?.closest?.(".cell-editor")) {
        visualEditor.querySelector(".cell-editor, .raw-block")?.focus();
      }
    }
    if (!searchPanel.hidden) refreshSearch(0);
  }

  function insertPlainText(text) {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return;
    const range = selection.getRangeAt(0);
    range.deleteContents();
    const node = document.createTextNode(text);
    range.insertNode(node);
    range.setStartAfter(node);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function pastedTables(text) {
    const parsed = parseMarkdown(text);
    return parsed.some((block) => block.type === "table") ? parsed : null;
  }

  function isOnlyEmptyBlock() {
    return (
      blocks.length === 1 &&
      blocks[0].type === "text" &&
      blocks[0].lines.join("").length === 0
    );
  }

  visualEditor.addEventListener("beforeinput", (event) => {
    const editable = event.target.closest(".cell-editor, .raw-block");
    if (!editable) return;
    const identity = editable.classList.contains("cell-editor")
      ? `${editable.dataset.blockIndex}:${editable.dataset.rowIndex}:${editable.dataset.columnIndex}`
      : `text:${editable.dataset.blockIndex}`;
    const inputType = event.inputType || "edit";
    const groupedType = inputType === "insertText" || inputType === "insertCompositionText"
      ? "insertText"
      : inputType.startsWith("deleteContent")
        ? inputType
        : null;
    checkpoint(groupedType ? `${identity}:${groupedType}` : null);
  });

  sourceEditor.addEventListener("beforeinput", (event) => {
    const inputType = event.inputType || "edit";
    const groupedType = inputType === "insertText" || inputType === "insertCompositionText"
      ? "insertText"
      : inputType.startsWith("deleteContent")
        ? inputType
        : null;
    checkpoint(groupedType ? `source:${groupedType}` : null);
  });

  visualEditor.addEventListener("input", (event) => {
    const swatch = event.target.closest?.(".color-swatch");
    if (swatch) {
      applySwatchColor(swatch);
      return;
    }

    const cell = event.target.closest(".cell-editor");
    if (cell) {
      updateCell(cell);
      if (event.inputType === "insertFromPaste" || event.inputType === "deleteByCut") {
        queueMicrotask(() => {
          if (cell.isConnected) refreshCellDecoration(cell, true);
        });
      }
      return;
    }

    const raw = event.target.closest(".raw-block");
    if (raw) {
      blocks[Number(raw.dataset.blockIndex)].lines = normalizeNewlines(raw.innerText).split("\n");
    }
  });

  visualEditor.addEventListener("change", (event) => {
    const swatch = event.target.closest?.(".color-swatch");
    if (!swatch) return;
    applySwatchColor(swatch);
    delete swatch.dataset.historyStarted;
  });

  visualEditor.addEventListener("focusout", (event) => {
    const swatch = event.target.closest?.(".color-swatch");
    if (swatch) delete swatch.dataset.historyStarted;

    const cell = event.target.closest?.(".cell-editor");
    if (
      cell &&
      activeColorToken &&
      cell.contains(activeColorToken) &&
      event.relatedTarget &&
      colorPalette.contains(event.relatedTarget)
    ) {
      return;
    }
    if (!cell || (event.relatedTarget && cell.contains(event.relatedTarget))) return;
    refreshCellDecoration(cell);
    if (!searchPanel.hidden) refreshSearch(searchIndex < 0 ? 0 : searchIndex);
  });

  visualEditor.addEventListener("click", (event) => {
    const colorValueSwatch = event.target.closest(".color-expression-swatch");
    if (colorValueSwatch) {
      event.preventDefault();
      hideContextMenu();
      clearTableSelection();
      openColorPalette(colorValueSwatch.closest(".color-expression"), colorValueSwatch);
      return;
    }

    const tableSelector = event.target.closest('.table-selector[data-action="select-table"]');
    if (tableSelector) {
      event.preventDefault();
      selectTable(Number(tableSelector.dataset.blockIndex));
      return;
    }

    const button = event.target.closest(".row-control");
    if (!button) {
      if (event.target.closest(".cell-editor, .raw-block")) {
        clearTableSelection();
      }
      return;
    }
    const blockIndex = Number(button.dataset.blockIndex);
    const rowIndex = Number(button.dataset.rowIndex);
    if (button.dataset.action === "add-row") {
      addRow(blockIndex, rowIndex);
    } else {
      deleteRow(blockIndex, rowIndex);
    }
  });

  visualEditor.addEventListener("dblclick", (event) => {
    if (event.target.closest(".color-swatch, .color-expression-swatch")) return;
    const cell = event.target.closest(".cell-editor");
    if (!cell || event.ctrlKey || event.metaKey || event.altKey) return;
    if (selectAsciiTokenAtPoint(cell, event.clientX, event.clientY)) {
      event.preventDefault();
    }
  });

  visualEditor.addEventListener("paste", (event) => {
    const text = normalizeNewlines(event.clipboardData?.getData("text/plain") ?? "");
    const parsed = pastedTables(text);

    if (parsed) {
      event.preventDefault();
      checkpoint();
      if (isOnlyEmptyBlock()) {
        blocks = parsed;
      } else {
        const targetBlock = event.target.closest("[data-block-index]");
        const blockIndex = targetBlock ? Number(targetBlock.dataset.blockIndex) : blocks.length - 1;
        blocks.splice(blockIndex + 1, 0, ...parsed);
      }
      renderVisual();
      const firstTableCell = visualEditor.querySelector(".md-table .cell-editor");
      firstTableCell?.focus();
      return;
    }

    const editable = event.target.closest(".cell-editor, .raw-block");
    if (editable) {
      event.preventDefault();
      checkpoint();
      insertPlainText(text);
      editable.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertFromPaste" }));
    }
  });

  visualEditor.addEventListener("contextmenu", (event) => {
    const figure = event.target.closest(".table-figure");
    if (!figure) {
      hideContextMenu();
      return;
    }

    event.preventDefault();
    const cell = event.target.closest(".cell-editor");
    showContextMenu(event, figure, cell);
  });

  contextMenu.addEventListener("pointerdown", (event) => {
    event.preventDefault();
  });

  colorPalette.addEventListener("input", (event) => {
    const control = event.target.closest("input[data-stop-index]");
    if (!control) return;
    const stopIndex = Number(control.dataset.stopIndex);
    if (control.type === "color") {
      applyCompoundStopColor(stopIndex, control.value);
    } else if (control.type === "number") {
      applyCompoundStopPosition(stopIndex, control.value);
    }
  });

  colorPalette.addEventListener("change", (event) => {
    const control = event.target.closest('input[type="number"][data-stop-index]');
    if (!control || !activeColorToken) return;
    const value = colorValueMetadata.get(activeColorToken);
    const stop = value?.stops[Number(control.dataset.stopIndex)];
    if (!stop) return;
    const position = Number(control.value);
    if (!Number.isFinite(position) || position < 0 || position > 100) {
      control.value = formatStopPosition(stop.position);
      return;
    }
    control.value = formatStopPosition(position);
  });

  colorPalette.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action][data-stop-index]");
    if (!button || button.disabled) return;
    const stopIndex = Number(button.dataset.stopIndex);
    if (button.dataset.action === "add-color-stop") {
      addCompoundColorStop(stopIndex);
    } else if (button.dataset.action === "delete-color-stop") {
      deleteCompoundColorStop(stopIndex);
    }
  });

  contextMenu.addEventListener("click", (event) => {
    const item = event.target.closest("button[data-action]");
    if (!item || item.disabled || !contextTarget) return;

    const target = contextTarget;
    const action = item.dataset.action;
    hideContextMenu();

    if (action === "undo") {
      undoDocument();
    } else if (action === "redo") {
      redoDocument();
    } else if (action === "cut-text") {
      copyTextFromMenu(target, true);
    } else if (action === "copy-text") {
      copyTextFromMenu(target, false);
    } else if (action === "paste-text") {
      pasteTextFromMenu(target);
    } else if (action === "select-all-text") {
      selectAllTextFromMenu(target);
    } else if (action === "find") {
      openSearch(false);
    } else if (action === "replace") {
      openSearch(true);
    } else if (action === "insert-gradient") {
      insertColorTemplateFromMenu(
        target,
        "g(0:#2DC3C7,40:#27A8AB,60:#F623D9,100:#F625B4)",
      );
    } else if (action === "insert-millefeuille") {
      insertColorTemplateFromMenu(target, "m(0:#FF0000,50:#0000FF)");
    } else if (action === "copy-table") {
      copyTableFromMenu(target.blockIndex);
    } else if (action === "add-row-before") {
      addRow(target.blockIndex, target.rowIndex - 1, target.columnIndex);
    } else if (action === "add-row-after") {
      addRow(target.blockIndex, target.rowIndex, target.columnIndex);
    } else if (action === "delete-row") {
      deleteRow(target.blockIndex, target.rowIndex, target.columnIndex);
    } else if (action === "delete-table") {
      deleteTable(target.blockIndex);
    }
  });

  visualEditor.addEventListener("keydown", (event) => {
    const cell = event.target.closest(".cell-editor");
    if (!cell) return;
    if (event.isComposing || event.keyCode === 229) return;
    const position = cellPosition(cell);
    const table = blocks[position.blockIndex];

    if (event.key === "Escape") {
      event.preventDefault();
      selectTable(position.blockIndex);
      return;
    }

    if ((event.ctrlKey || event.metaKey) && !event.shiftKey && event.key === "Enter") {
      event.preventDefault();
      const rowIndex = position.rowIndex === -1 ? -1 : position.rowIndex;
      addRow(position.blockIndex, rowIndex, position.columnIndex);
      return;
    }

    if (event.shiftKey && event.key === "Enter") {
      event.preventDefault();
      checkpoint();
      insertPlainText("\n");
      cell.dispatchEvent(
        new InputEvent("input", { bubbles: true, inputType: "insertLineBreak" }),
      );
      return;
    }

    if (
      (event.ctrlKey || event.metaKey) &&
      event.shiftKey &&
      event.key === "Backspace" &&
      position.rowIndex >= 0
    ) {
      event.preventDefault();
      deleteRow(position.blockIndex, position.rowIndex, position.columnIndex);
      return;
    }

    if (event.key === "Enter") {
      event.preventDefault();
      const nextRow = position.rowIndex + 1;
      if (nextRow < table.rows.length) {
        focusCell(position.blockIndex, nextRow, position.columnIndex);
      }
      return;
    }

    if (
      !event.shiftKey &&
      !event.ctrlKey &&
      !event.metaKey &&
      !event.altKey &&
      (event.key === "ArrowLeft" || event.key === "ArrowRight")
    ) {
      const caretOffset = caretOffsetInCell(cell);
      const backward = event.key === "ArrowLeft";
      const atBoundary = backward ? caretOffset === 0 : caretOffset === cell.textContent.length;
      if (atBoundary && moveHorizontalCell(position, table, backward)) {
        event.preventDefault();
      }
      return;
    }

    if (event.key !== "Tab" || event.ctrlKey || event.metaKey) return;
    event.preventDefault();

    const columns = table.header.length;
    const logicalRow = position.rowIndex + 1;
    let next = logicalRow * columns + position.columnIndex + (event.shiftKey ? -1 : 1);
    const total = (table.rows.length + 1) * columns;

    if (next >= total) {
      addRow(position.blockIndex, table.rows.length - 1, 0);
      return;
    }
    next = Math.max(0, next);
    const nextLogicalRow = Math.floor(next / columns);
    focusCell(position.blockIndex, nextLogicalRow - 1, next % columns, event.shiftKey);
  });

  document.addEventListener("keydown", (event) => {
    if (!colorPalette.hidden && event.key === "Escape") {
      event.preventDefault();
      closeColorPalette();
      return;
    }

    if (!contextMenu.hidden && event.key === "Escape") {
      event.preventDefault();
      hideContextMenu();
      return;
    }

    if (!searchPanel.hidden && event.key === "Escape") {
      event.preventDefault();
      closeSearch();
      return;
    }

    const modifier = event.ctrlKey || event.metaKey;
    if (modifier && event.key.toLowerCase() === "f") {
      event.preventDefault();
      openSearch(false);
      return;
    }

    if (modifier && event.key.toLowerCase() === "h") {
      event.preventDefault();
      openSearch(true);
      return;
    }

    if (event.key === "F3") {
      event.preventDefault();
      if (searchPanel.hidden) openSearch(false);
      else moveSearch(event.shiftKey ? -1 : 1);
      return;
    }

    if (!event.target.closest("#search-panel") && modifier && event.key.toLowerCase() === "z") {
      event.preventDefault();
      if (event.shiftKey) redoDocument();
      else undoDocument();
      return;
    }

    if (!event.target.closest("#search-panel") && modifier && event.key.toLowerCase() === "y") {
      event.preventDefault();
      redoDocument();
      return;
    }

    if (
      !sourceMode &&
      selectedTableIndex !== null &&
      (event.key === "Delete" || event.key === "Backspace")
    ) {
      event.preventDefault();
      deleteTable(selectedTableIndex);
      return;
    }

    if ((event.ctrlKey || event.metaKey) && event.key === "/") {
      event.preventDefault();
      toggleSourceMode();
      return;
    }

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
    }
  });

  document.addEventListener("copy", (event) => {
    writeSelectedTableToClipboard(event);
  });

  document.addEventListener("cut", (event) => {
    if (!writeSelectedTableToClipboard(event)) return;
    deleteTable(selectedTableIndex);
  });

  document.addEventListener("pointerdown", (event) => {
    if (!contextMenu.hidden && !event.target.closest("#table-context-menu")) {
      hideContextMenu();
    }
    if (
      !colorPalette.hidden &&
      !event.target.closest("#color-value-palette") &&
      !event.target.closest(".color-expression-swatch")
    ) {
      closeColorPalette();
    }
  });

  window.addEventListener("blur", hideContextMenu);
  window.addEventListener("resize", hideContextMenu);
  window.addEventListener("scroll", hideContextMenu, true);
  window.addEventListener("resize", closeColorPalette);
  window.addEventListener("scroll", closeColorPalette, true);

  findInput.addEventListener("input", () => refreshSearch(0));
  findInput.addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    moveSearch(event.shiftKey ? -1 : 1);
  });
  document.querySelector("#find-previous").addEventListener("click", () => moveSearch(-1));
  document.querySelector("#find-next").addEventListener("click", () => moveSearch(1));
  document.querySelector("#close-search").addEventListener("click", closeSearch);
  document.querySelector("#replace-current").addEventListener("click", replaceCurrentMatch);
  document.querySelector("#replace-all").addEventListener("click", replaceAllMatches);

  window.addEventListener("pagehide", () => {
    sourceEditor.value = "";
    blocks = [{ type: "text", lines: [""] }];
  });

  renderVisual();
})();
