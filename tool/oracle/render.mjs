import { mathjax } from '@mathjax/src/mjs/mathjax.js';
import { TeX } from '@mathjax/src/mjs/input/tex.js';
import TexError from '@mathjax/src/mjs/input/tex/TexError.js';
import { SVG } from '@mathjax/src/mjs/output/svg.js';
import { liteAdaptor } from '@mathjax/src/mjs/adaptors/liteAdaptor.js';
import { LiteElement } from '@mathjax/src/mjs/adaptors/lite/Element.js';
import { RegisterHTMLHandler } from '@mathjax/src/mjs/handlers/html.js';
import { MathJaxNewcmFont } from '@mathjax/mathjax-newcm-font/mjs/svg.js';
import { Loader, CONFIG as LOADERCONFIG } from '@mathjax/src/mjs/components/loader.js';
import { Package } from '@mathjax/src/mjs/components/package.js';
import { dependencies } from '@mathjax/src/components/mjs/dependencies.js';
import { source } from '@mathjax/src/components/mjs/source.js';

import '@mathjax/src/mjs/input/tex/action/ActionConfiguration.js';
import '@mathjax/src/mjs/input/tex/ams/AmsConfiguration.js';
import '@mathjax/src/mjs/input/tex/amscd/AmsCdConfiguration.js';
import '@mathjax/src/mjs/input/tex/autoload/AutoloadConfiguration.js';
import '@mathjax/src/mjs/input/tex/base/BaseConfiguration.js';
import '@mathjax/src/mjs/input/tex/bbm/BbmConfiguration.js';
import '@mathjax/src/mjs/input/tex/bboldx/BboldxConfiguration.js';
import '@mathjax/src/mjs/input/tex/bbox/BboxConfiguration.js';
import '@mathjax/src/mjs/input/tex/begingroup/BegingroupConfiguration.js';
import '@mathjax/src/mjs/input/tex/boldsymbol/BoldsymbolConfiguration.js';
import '@mathjax/src/mjs/input/tex/braket/BraketConfiguration.js';
import '@mathjax/src/mjs/input/tex/bussproofs/BussproofsConfiguration.js';
import '@mathjax/src/mjs/input/tex/cancel/CancelConfiguration.js';
import '@mathjax/src/mjs/input/tex/cases/CasesConfiguration.js';
import '@mathjax/src/mjs/input/tex/centernot/CenternotConfiguration.js';
import '@mathjax/src/mjs/input/tex/color/ColorConfiguration.js';
import '@mathjax/src/mjs/input/tex/colortbl/ColortblConfiguration.js';
import '@mathjax/src/mjs/input/tex/colorv2/ColorV2Configuration.js';
import '@mathjax/src/mjs/input/tex/configmacros/ConfigMacrosConfiguration.js';
import '@mathjax/src/mjs/input/tex/dsfont/DsfontConfiguration.js';
import '@mathjax/src/mjs/input/tex/empheq/EmpheqConfiguration.js';
import '@mathjax/src/mjs/input/tex/enclose/EncloseConfiguration.js';
import '@mathjax/src/mjs/input/tex/extpfeil/ExtpfeilConfiguration.js';
import '@mathjax/src/mjs/input/tex/fontsizev3/FontSizeV3Configuration.js';
import '@mathjax/src/mjs/input/tex/gensymb/GensymbConfiguration.js';
import '@mathjax/src/mjs/input/tex/html/HtmlConfiguration.js';
import '@mathjax/src/mjs/input/tex/mathtools/MathtoolsConfiguration.js';
import '@mathjax/src/mjs/input/tex/mhchem/MhchemConfiguration.js';
import '@mathjax/src/mjs/input/tex/newcommand/NewcommandConfiguration.js';
import '@mathjax/src/mjs/input/tex/noerrors/NoErrorsConfiguration.js';
import '@mathjax/src/mjs/input/tex/noundefined/NoUndefinedConfiguration.js';
import '@mathjax/src/mjs/input/tex/physics/PhysicsConfiguration.js';
import '@mathjax/src/mjs/input/tex/require/RequireConfiguration.js';
import '@mathjax/src/mjs/input/tex/setoptions/SetOptionsConfiguration.js';
import '@mathjax/src/mjs/input/tex/tagformat/TagFormatConfiguration.js';
import '@mathjax/src/mjs/input/tex/texhtml/TexHtmlConfiguration.js';
import '@mathjax/src/mjs/input/tex/textcomp/TextcompConfiguration.js';
import '@mathjax/src/mjs/input/tex/textmacros/TextMacrosConfiguration.js';
import '@mathjax/src/mjs/input/tex/unicode/UnicodeConfiguration.js';
import '@mathjax/src/mjs/input/tex/units/UnitsConfiguration.js';
import '@mathjax/src/mjs/input/tex/upgreek/UpgreekConfiguration.js';
import '@mathjax/src/mjs/input/tex/verb/VerbConfiguration.js';

const MATHJAX_VERSION = '4.1.3';
const FONT_NAME = 'mathjax-newcm';

const DEFAULT_PACKAGES = [
  'base',
  'action',
  'ams',
  'amscd',
  'bbox',
  'boldsymbol',
  'braket',
  'bussproofs',
  'cancel',
  'cases',
  'centernot',
  'color',
  'colortbl',
  'empheq',
  'enclose',
  'extpfeil',
  'gensymb',
  'html',
  'mathtools',
  'mhchem',
  'newcommand',
  'upgreek',
  'unicode',
  'verb',
  'configmacros',
  'tagformat',
  'textcomp',
  'textmacros',
  'require',
];

const ALL_TEX_PACKAGES = [
  'action',
  'ams',
  'amscd',
  'autoload',
  'bbm',
  'bboldx',
  'bbox',
  'begingroup',
  'boldsymbol',
  'braket',
  'bussproofs',
  'cancel',
  'cases',
  'centernot',
  'color',
  'colortbl',
  'colorv2',
  'configmacros',
  'dsfont',
  'empheq',
  'enclose',
  'extpfeil',
  'fontsizev3',
  'gensymb',
  'html',
  'mathtools',
  'mhchem',
  'newcommand',
  'noerrors',
  'noundefined',
  'physics',
  'require',
  'setoptions',
  'tagformat',
  'texhtml',
  'textcomp',
  'textmacros',
  'unicode',
  'units',
  'upgreek',
  'verb',
];

const ALLOWED_TEX_PACKAGE_SET = new Set(ALL_TEX_PACKAGES);
const ALLOWED_REQUEST_PACKAGES = new Set(['base', ...ALL_TEX_PACKAGES]);
const ALLOWED_DYNAMIC_FONT_CHUNK_RE =
  /^@mathjax\/mathjax-[a-z0-9-]+\/(?:js|mjs)\/(?:svg|chtml)\/dynamic\/[A-Za-z0-9_-]+\.js$/;
const ALLOWED_TEX_MODULE_PATHS = new Set(
  ALL_TEX_PACKAGES.map((pkg) => `[tex]/${pkg}`)
    .filter((spec) => Object.hasOwn(source, spec))
    .map((spec) => source[spec]),
);

let allowTexHtml = false;

function hasUnsafePathTokens(specifier) {
  if (
    typeof specifier !== 'string' ||
    specifier.length === 0 ||
    /[\0\\?#%]/.test(specifier)
  ) {
    return true;
  }
  const segments = specifier.split('/');
  return segments.some(
    (segment) => segment.length === 0 || segment === '.' || segment === '..',
  );
}

function resolveSafeAsyncLoadTarget(name) {
  if (hasUnsafePathTokens(name)) {
    return null;
  }
  if (name.startsWith('[tex]/')) {
    const pkg = name.slice('[tex]/'.length);
    if (!ALLOWED_TEX_PACKAGE_SET.has(pkg)) {
      return null;
    }
    if (pkg === 'texhtml' && !allowTexHtml) {
      return null;
    }
    if (!Object.hasOwn(LOADERCONFIG.source, name)) {
      return null;
    }
    return Package.resolvePath(name);
  }
  if (ALLOWED_DYNAMIC_FONT_CHUNK_RE.test(name)) {
    return name;
  }
  return null;
}

function isAllowedRequireTarget(file) {
  if (typeof file !== 'string' || file.length === 0 || /[\0?#%]/.test(file)) {
    return false;
  }
  if (ALLOWED_TEX_MODULE_PATHS.has(file)) {
    if (!allowTexHtml && file === source['[tex]/texhtml']) {
      return false;
    }
    return true;
  }
  return (
    !hasUnsafePathTokens(file) && ALLOWED_DYNAMIC_FONT_CHUNK_RE.test(file)
  );
}

// LiteElement lacks addEventListener, which SvgMaction invokes for interactive nodes.
if (typeof LiteElement.prototype.addEventListener !== 'function') {
  LiteElement.prototype.addEventListener = () => {};
}

Object.assign(LOADERCONFIG.dependencies, dependencies);
Object.assign(LOADERCONFIG.source, source);
LOADERCONFIG.require = async (file) => {
  if (!isAllowedRequireTarget(file)) {
    throw new Error(`Disallowed MathJax require target: ${String(file)}`);
  }
  return import(file);
};
mathjax.asyncLoad = async (name) => {
  const target = resolveSafeAsyncLoadTarget(name);
  if (!target) {
    throw new Error(`Disallowed MathJax asyncLoad specifier: ${String(name)}`);
  }
  return import(target);
};

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const sharedFont = new MathJaxNewcmFont();

function round6(value) {
  const rounded = Math.round(value * 1e6) / 1e6;
  return Object.is(rounded, -0) ? 0 : rounded;
}

function mapTexErrorClass(err) {
  const id = err?.id ?? '';
  const msg = err?.message ?? '';
  switch (id) {
    case 'UndefinedControlSequence':
      return 'undefinedControlSequence';
    case 'MissingCloseBrace':
    case 'MissingOpenForSub':
    case 'MissingOpenForSup':
    case 'MissingCloseBracket':
    case 'ExtraOpenMissingClose':
      return 'missingBrace';
    case 'ExtraCloseMissingOpen':
    case 'ExtraCloseLooking':
      return 'extraBrace';
    case 'Misplaced':
      if (
        msg.includes('\\cr') ||
        msg.includes('\\hline') ||
        msg.includes('\\hdashline')
      ) {
        return 'misplacedNewline';
      }
      return 'misplacedAlignmentTab';
    case 'ExtraAlignTab':
    case 'XalignOverflow':
    case 'ExtraCasesAlignTab':
    case 'MultlineRowsOneCol':
      return 'misplacedAlignmentTab';
    case 'BracketMustBeDimension':
      return 'misplacedNewline';
    case 'MissingOrUnrecognizedDelim':
    case 'ExtraLeftMissingRight':
      return 'missingDelimiter';
    case 'MissingLeftExtraRight':
    case 'ExtraMiddle':
      return 'extraDelimiter';
    case 'EnvBadEnd':
    case 'EnvMissingEnd':
    case 'MissingBeginExtraEnd':
    case 'ErroneousNestingEq':
      return 'mismatchedEnvironment';
    case 'DoubleExponent':
    case 'DoubleSubscripts':
    case 'DoubleExponentPrime':
      return 'doubleScript';
    case 'MissingArgFor':
    case 'MissingBoxFor':
    case 'MissingArgForColumn':
    case 'MissingDimOrUnits':
    case 'MissingColumnDimOrUnits':
    case 'NoClosingDelim':
    case 'TokenNotFoundForCommand':
    case 'MissingProofCommand':
      return 'missingArgument';
    case 'MissingCS':
    case 'IllegalControlSequenceName':
    case 'IllegalParamNumber':
    case 'CantUseHash1':
    case 'CantUseHash2':
    case 'SequentialParam':
    case 'MissingReplacementString':
    case 'ProtectedMacro':
    case 'IllegalMacroParam':
    case 'RunawayArgument':
    case 'MismatchUseDef':
      return 'invalidMacroDefinition';
    case 'MaxMacroSub1':
    case 'MaxMacroSub2':
    case 'MaxBufferSize':
    case 'MaxTemplateSubs':
      return 'budgetExceeded';
    case 'UnknownEnv':
      return 'unknownEnvironment';
    default:
      return 'syntaxError';
  }
}

function mulMatrix(m1, m2) {
  return [
    m1[0] * m2[0] + m1[2] * m2[1],
    m1[1] * m2[0] + m1[3] * m2[1],
    m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4],
    m1[1] * m2[4] + m1[3] * m2[5] + m1[5],
  ];
}

function parseTransform(transformStr) {
  let matrix = [1, 0, 0, 1, 0, 0];
  if (!transformStr) {
    return matrix;
  }
  const opRegex = /(translate|scale|matrix|rotate)\s*\(([^)]*)\)/g;
  let match;
  while ((match = opRegex.exec(transformStr)) !== null) {
    const kind = match[1];
    const args = match[2]
      .trim()
      .split(/[\s,]+/)
      .filter((s) => s.length > 0)
      .map(Number);
    let op = [1, 0, 0, 1, 0, 0];
    if (kind === 'translate' && args.length >= 1) {
      op = [1, 0, 0, 1, args[0], args[1] ?? 0];
    } else if (kind === 'scale' && args.length >= 1) {
      const sx = args[0];
      const sy = args[1] ?? sx;
      op = [sx, 0, 0, sy, 0, 0];
    } else if (kind === 'matrix' && args.length === 6) {
      op = args;
    } else if (kind === 'rotate' && args.length >= 1) {
      const rad = (args[0] * Math.PI) / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);
      const cx = args[1] ?? 0;
      const cy = args[2] ?? 0;
      op = [cos, sin, -sin, cos, cx, cy];
      if (cx !== 0 || cy !== 0) {
        op = mulMatrix([1, 0, 0, 1, cx, cy], [cos, sin, -sin, cos, 0, 0]);
        op = mulMatrix(op, [1, 0, 0, 1, -cx, -cy]);
      }
    }
    matrix = mulMatrix(matrix, op);
  }
  return matrix;
}

function parseViewBox(viewBoxStr) {
  if (!viewBoxStr) {
    return null;
  }
  const parts = viewBoxStr
    .trim()
    .split(/[\s,]+/)
    .map(Number);
  if (parts.length !== 4 || parts.some(Number.isNaN)) {
    return null;
  }
  return parts;
}

function isHiddenHelperRect(attrs) {
  return (
    attrs['data-hitbox'] === 'true' ||
    attrs['pointer-events'] === 'all' ||
    attrs['data-background'] === 'true'
  );
}

function extractSvgGeometry(svgEl) {
  const viewBoxStr =
    adaptor.getAttribute(svgEl, 'data-mjx-viewBox') ||
    adaptor.getAttribute(svgEl, 'viewBox');
  const viewBox = parseViewBox(viewBoxStr) || [0, 0, 0, 0];
  const [, vbY, vbW, vbH] = viewBox;

  const verticalAlign = adaptor.getStyle(svgEl, 'vertical-align');
  const box = {
    width: round6(vbW / 1000),
    height: round6(-vbY / 1000),
    depth:
      verticalAlign === '0' || verticalAlign === '0ex'
        ? 0
        : round6((vbH + vbY) / 1000),
  };

  const glyphs = [];
  const rules = [];

  function walk(node, matrix, isRootContainer, isTopTableSubSvg) {
    const kind = adaptor.kind(node);
    if (kind === '#text' || kind === '#comment' || kind === 'defs') {
      return;
    }

    const attrs = node.attributes || {};

    if (kind === 'use') {
      const codeHex = attrs['data-c'];
      if (codeHex) {
        const local = parseTransform(attrs.transform);
        const m = mulMatrix(matrix, local);
        const scaleX =
          m[1] === 0 && m[2] === 0 ? m[0] : Math.hypot(m[0], m[1]);
        const scaleY =
          m[1] === 0 && m[2] === 0 ? m[3] : Math.hypot(m[2], m[3]);
        glyphs.push({
          codePoint: parseInt(codeHex, 16),
          x: round6(m[4] / 1000),
          y: round6(m[5] / 1000),
          scaleX: round6(scaleX),
          scaleY: round6(scaleY),
        });
      }
      return;
    }

    if (kind === 'path' && attrs['data-c']) {
      const local = parseTransform(attrs.transform);
      const m = mulMatrix(matrix, local);
      const scaleX = m[1] === 0 && m[2] === 0 ? m[0] : Math.hypot(m[0], m[1]);
      const scaleY = m[1] === 0 && m[2] === 0 ? m[3] : Math.hypot(m[2], m[3]);
      glyphs.push({
        codePoint: parseInt(attrs['data-c'], 16),
        x: round6(m[4] / 1000),
        y: round6(m[5] / 1000),
        scaleX: round6(scaleX),
        scaleY: round6(scaleY),
      });
      return;
    }

    if (kind === 'rect') {
      if (!isHiddenHelperRect(attrs)) {
        const local = parseTransform(attrs.transform);
        const m = mulMatrix(matrix, local);
        const rx = Number(attrs.x ?? 0);
        const ry = Number(attrs.y ?? 0);
        const rw = Number(attrs.width ?? 0);
        const rh = Number(attrs.height ?? 0);
        const x1 = m[0] * rx + m[2] * ry + m[4];
        const y1 = m[1] * rx + m[3] * ry + m[5];
        const x2 = m[0] * (rx + rw) + m[2] * (ry + rh) + m[4];
        const y2 = m[1] * (rx + rw) + m[3] * (ry + rh) + m[5];
        rules.push({
          x: round6(Math.min(x1, x2) / 1000),
          y: round6(Math.min(y1, y2) / 1000),
          width: round6(Math.abs(x2 - x1) / 1000),
          height: round6(Math.abs(y2 - y1) / 1000),
        });
      }
      return;
    }

    if (kind === 'svg') {
      const subVb = parseViewBox(attrs.viewBox);
      if (attrs['data-table'] === 'true' || attrs['data-labels'] === 'true') {
        const subVbX = subVb ? subVb[0] : 0;
        const align = (attrs.preserveAspectRatio || '').slice(0, 4);
        const tx =
          align === 'xMin'
            ? 0
            : align === 'xMax'
              ? vbW - subVbX
              : vbW / 2 - subVbX;
        const nextMatrix = [1, 0, 0, 1, tx, 0];
        for (const child of adaptor.childNodes(node)) {
          walk(child, nextMatrix, false, true);
        }
        return;
      }

      if (subVb && attrs.width !== undefined && attrs.height !== undefined) {
        const sx = Number(attrs.width) / subVb[2];
        const sy = Number(attrs.height) / subVb[3];
        const x = Number(attrs.x ?? 0);
        const y = Number(attrs.y ?? 0);
        const subMatrix = [
          sx,
          0,
          0,
          sy,
          x - subVb[0] * sx,
          y - subVb[1] * sy,
        ];
        const nextMatrix = mulMatrix(matrix, subMatrix);
        for (const child of adaptor.childNodes(node)) {
          walk(child, nextMatrix, false, false);
        }
        return;
      }
    }

    let nextMatrix = matrix;
    if (kind === 'g' && (isRootContainer || isTopTableSubSvg)) {
      // Unwrap MathJax's root/subtable Y-inversion wrapper so math coords stay Y-up in ems.
      nextMatrix = matrix;
    } else if (attrs.transform) {
      nextMatrix = mulMatrix(matrix, parseTransform(attrs.transform));
    }

    for (const child of adaptor.childNodes(node)) {
      walk(child, nextMatrix, false, false);
    }
  }

  for (const child of adaptor.childNodes(svgEl)) {
    walk(child, [1, 0, 0, 1, 0, 0], true, false);
  }

  return { box, glyphs, rules };
}

function errorResult(id, errorClass, errorMessage, mathjaxErrorId = null) {
  return {
    id,
    accepted: false,
    errorClass,
    errorMessage,
    mathjaxErrorId,
    box: null,
    glyphs: [],
    rules: [],
  };
}

async function renderCase(item, includeSvg) {
  if (item.packages !== undefined && !Array.isArray(item.packages)) {
    return errorResult(
      item.id,
      'syntaxError',
      'Invalid packages configuration; expected an array of package names',
    );
  }
  const packages = Array.isArray(item.packages)
    ? item.packages
    : DEFAULT_PACKAGES;
  for (const pkg of packages) {
    if (typeof pkg !== 'string' || !ALLOWED_REQUEST_PACKAGES.has(pkg)) {
      return errorResult(
        item.id,
        'syntaxError',
        `Unsupported or disallowed TeX package "${String(pkg)}"`,
      );
    }
    if (pkg === 'texhtml' && !allowTexHtml) {
      return errorResult(
        item.id,
        'syntaxError',
        'TeX package "texhtml" is disallowed unless --allow-texhtml is passed',
      );
    }
  }
  const allowNoErrors = packages.includes('noerrors');
  const display =
    item.display === true || item.display === 'display';

  let capturedError = null;
  const texOptions = {
    packages,
    formatError: (jax, err) => {
      if (allowNoErrors) {
        return jax.formatError(err);
      }
      capturedError = err;
      throw err;
    },
  };
  if (allowTexHtml && packages.includes('texhtml')) {
    texOptions.allowTexHTML = true;
  } else if (!allowTexHtml && packages.includes('setoptions')) {
    texOptions.setoptions = {
      allowOptions: {
        texhtml: false,
      },
    };
  }
  if (item.macros && packages.includes('configmacros')) {
    texOptions.macros = item.macros;
  }

  const texJax = new TeX(texOptions);
  const svgJax = new SVG({
    fontData: sharedFont,
    fontCache: 'local',
    linebreaks: { inline: false },
  });
  const doc = mathjax.document('', {
    InputJax: texJax,
    OutputJax: svgJax,
  });

  try {
    const container = await doc.convertPromise(String(item.tex ?? ''), {
      display,
    });
    const svgEl =
      adaptor.kind(container) === 'svg'
        ? container
        : adaptor.tags(container, 'svg')[0];
    if (!svgEl) {
      return errorResult(item.id, 'syntaxError', 'No SVG element produced');
    }

    const { box, glyphs, rules } = extractSvgGeometry(svgEl);
    const result = {
      id: item.id,
      accepted: true,
      errorClass: null,
      errorMessage: null,
      box,
      glyphs,
      rules,
    };
    if (includeSvg) {
      result.svg = adaptor.outerHTML(svgEl);
    }
    return result;
  } catch (err) {
    const texErr = capturedError ?? (err instanceof TexError ? err : null);
    if (texErr) {
      return errorResult(
        item.id,
        mapTexErrorClass(texErr),
        texErr.message,
        texErr.id,
      );
    }
    return errorResult(
      item.id,
      'syntaxError',
      err instanceof Error ? err.message : String(err),
    );
  }
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const includeSvg = args.has('--include-svg');
  allowTexHtml = args.has('--allow-texhtml');

  const preloadedPackages = allowTexHtml
    ? ALL_TEX_PACKAGES
    : ALL_TEX_PACKAGES.filter((pkg) => pkg !== 'texhtml');
  Loader.preLoaded(
    'input/tex-base',
    ...preloadedPackages.map((pkg) => `[tex]/${pkg}`),
  );

  const rawInput = await readStdin();
  const trimmed = rawInput.trim();
  const parsed = trimmed.length === 0 ? [] : JSON.parse(trimmed);
  const items = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed.cases)
      ? parsed.cases
      : [parsed];

  const results = [];
  for (const item of items) {
    results.push(await renderCase(item, includeSvg));
  }

  process.stdout.write(
    JSON.stringify({
      mathjaxVersion: MATHJAX_VERSION,
      font: FONT_NAME,
      results,
    }) + '\n',
  );
}

main().catch((err) => {
  process.stderr.write(
    `oracle error: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`,
  );
  process.exitCode = 1;
});
