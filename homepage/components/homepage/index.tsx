// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

import { useEffect, useRef, useState } from '@lynx-js/react';
import './index.scss';

import ExplorerIconDark from '@assets/images/explorer-dark.png?inline';
import ExplorerIcon from '@assets/images/explorer.png?inline';
import ForwardIconDark from '@assets/images/forward-dark.png?inline';
import ForwardIcon from '@assets/images/forward.png?inline';
import ScanIconDark from '@assets/images/scan-dark.png?inline';
import ScanIcon from '@assets/images/scan.png?inline';
import ShowcaseIcon from '@assets/images/showcase.png?inline';
import type { InputEvent } from '../../typing';
import { openSchema, navigateTo, useTheme, useSafeArea } from '@explorer/lib';

interface HomePageProps {
  showPage: boolean;
}

const RECENT_SCHEMAS_STORAGE_KEY = 'recentSchemas';
const MAX_RECENT_SCHEMAS = 3;
const HTTP_SCHEMA_PATTERN = /^https?:\/\//i;
const LOCAL_SCHEMA_PATTERN = /^file:\/\/lynx\?local:\/\//i;
const RECENT_DELETE_ACTION_WIDTH = 88;
const RECENT_SWIPE_OPEN_THRESHOLD = 44;
const GENERIC_PATH_SEGMENTS = new Set(['dist', 'build', 'bundle', 'bundles', 'out']);

function getExplorerModule() {
  if (typeof NativeModules !== 'undefined') {
    return NativeModules.ExplorerModule;
  }
  return globalThis.NativeModules?.ExplorerModule;
}

function readRecentSchemas(): string[] {
  const raw =
    getExplorerModule()?.readFromLocalStorage?.(RECENT_SCHEMAS_STORAGE_KEY) ||
    '[]';
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return parsed
        .filter((item): item is string => typeof item === 'string')
        .slice(0, MAX_RECENT_SCHEMAS);
    }
  } catch {}
  return [];
}

function writeRecentSchemas(recentSchemas: string[]) {
  getExplorerModule()?.saveToLocalStorage?.(
    RECENT_SCHEMAS_STORAGE_KEY,
    JSON.stringify(recentSchemas)
  );
}

function isSameRecentSchemas(left: string[], right: string[]) {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function isSupportedBundleUrl(url: string) {
  const normalizedUrl = url.trim();
  if (!normalizedUrl) {
    return false;
  }
  return HTTP_SCHEMA_PATTERN.test(normalizedUrl) || LOCAL_SCHEMA_PATTERN.test(normalizedUrl);
}

function getRecentDisplayText(url: string) {
  const normalizedUrl = url.trim();
  const schemaMatch = normalizedUrl.match(/^[a-z]+:\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?/i);
  if (!schemaMatch) {
    return {
      primaryText: normalizedUrl,
      secondaryText: '',
    };
  }

  const host = schemaMatch[1] || '';
  const pathname = schemaMatch[2] || '';
  const query = schemaMatch[3] || '';
  const pathSegments = pathname.split('/').filter((segment) => segment.length > 0);
  const fileName = pathSegments[pathSegments.length - 1] || '';
  const entryMatch = fileName.match(/^(.*)\.lynx\.bundle$/i);
  const entryName = entryMatch?.[1] || '';
  const reversedParents = pathSegments.slice(0, -1).reverse();
  const meaningfulParent = reversedParents.find(
    (segment) => !GENERIC_PATH_SEGMENTS.has(segment.toLowerCase())
  );
  const primaryText = entryName || fileName || meaningfulParent || host || normalizedUrl;
  const secondaryParts = [meaningfulParent, host, query].filter(
    (part): part is string => typeof part === 'string' && part.length > 0 && part !== primaryText
  );

  return {
    primaryText,
    secondaryText: secondaryParts.join(' · '),
  };
}

export default function HomePage(props: HomePageProps) {
  const { resolved, withTheme } = useTheme();
  const safeArea = useSafeArea();
  const [inputValue, setInputValue] = useState('');
  const [inputError, setInputError] = useState('');
  const [recentSchemas, setRecentSchemas] = useState<string[]>(
    () => readRecentSchemas()
  );
  const [openRecentUrl, setOpenRecentUrl] = useState<string | null>(null);
  const [activeSwipeUrl, setActiveSwipeUrl] = useState<string | null>(null);
  const [activeSwipeOffset, setActiveSwipeOffset] = useState(0);
  const recentSwipeRef = useRef<{
    url: string | null;
    startX: number;
    initialOffset: number;
    currentOffset: number;
  }>({
    url: null,
    startX: 0,
    initialOffset: 0,
    currentOffset: 0,
  });

  useEffect(() => {
    const syncRecentSchemas = () => {
      const latestRecentSchemas = readRecentSchemas();
      setRecentSchemas((prev) =>
        isSameRecentSchemas(prev, latestRecentSchemas) ? prev : latestRecentSchemas
      );
    };

    syncRecentSchemas();
    const timerId = setInterval(syncRecentSchemas, 1000);
    return () => clearInterval(timerId);
  }, []);

  useEffect(() => {
    if (openRecentUrl && !recentSchemas.includes(openRecentUrl)) {
      setOpenRecentUrl(null);
    }
  }, [openRecentUrl, recentSchemas]);

  const icons = {
    Scan: { dark: ScanIconDark, light: ScanIcon },
    Forward: { dark: ForwardIconDark, light: ForwardIcon },
    Explorer: { dark: ExplorerIconDark, light: ExplorerIcon },
  } as const;

  const openScan = () => {
    'background only';
    getExplorerModule()?.openScan?.();
  };

  const openSchemaWithUrl = (url: string) => {
    'background only';
    const normalizedUrl = url.trim();
    if (!normalizedUrl) {
      setInputError('Enter a bundle URL to continue.');
      return;
    }

    if (!isSupportedBundleUrl(normalizedUrl)) {
      setInputError('Enter a valid http(s) bundle URL or a file://lynx local bundle URL.');
      return;
    }

    setInputError('');
    if (HTTP_SCHEMA_PATTERN.test(normalizedUrl)) {
      setRecentSchemas((prev) => {
        const next = [normalizedUrl, ...prev.filter((item) => item !== normalizedUrl)].slice(
          0,
          MAX_RECENT_SCHEMAS
        );
        writeRecentSchemas(next);
        return next;
      });
    }
    setInputValue(normalizedUrl);
    openSchema(normalizedUrl);
  };

  const clearInput = () => {
    'background only';
    if (!inputValue) {
      return;
    }
    setInputError('');
    setInputValue('');
  };

  const removeRecentSchema = (url: string) => {
    'background only';
    if (openRecentUrl === url) {
      setOpenRecentUrl(null);
    }
    setRecentSchemas((prev) => {
      const next = prev.filter((item) => item !== url);
      writeRecentSchemas(next);
      return next;
    });
  };

  const clearRecentSchemas = () => {
    'background only';
    if (recentSchemas.length === 0) {
      return;
    }
    setOpenRecentUrl(null);
    setActiveSwipeUrl(null);
    setActiveSwipeOffset(0);
    recentSwipeRef.current = {
      url: null,
      startX: 0,
      initialOffset: 0,
      currentOffset: 0,
    };
    writeRecentSchemas([]);
    setRecentSchemas([]);
  };

  const handleRecentTouchStart = (url: string, event: { detail: { x: number } }) => {
    'background only';
    const initialOffset = openRecentUrl === url ? -RECENT_DELETE_ACTION_WIDTH : 0;
    recentSwipeRef.current = {
      url,
      startX: event.detail.x,
      initialOffset,
      currentOffset: initialOffset,
    };
    if (openRecentUrl && openRecentUrl !== url) {
      setOpenRecentUrl(null);
    }
    setActiveSwipeUrl(url);
    setActiveSwipeOffset(initialOffset);
  };

  const handleRecentTouchMove = (url: string, event: { detail: { x: number } }) => {
    'background only';
    if (recentSwipeRef.current.url !== url) {
      return;
    }
    const deltaX = event.detail.x - recentSwipeRef.current.startX;
    const nextOffset = clamp(
      recentSwipeRef.current.initialOffset + deltaX,
      -RECENT_DELETE_ACTION_WIDTH,
      0
    );
    recentSwipeRef.current.currentOffset = nextOffset;
    setActiveSwipeOffset(nextOffset);
  };

  const finalizeRecentSwipe = (url: string) => {
    'background only';
    if (recentSwipeRef.current.url !== url) {
      return;
    }
    const shouldOpen =
      recentSwipeRef.current.currentOffset <= -RECENT_SWIPE_OPEN_THRESHOLD;
    setOpenRecentUrl(shouldOpen ? url : null);
    setActiveSwipeUrl(null);
    setActiveSwipeOffset(0);
    recentSwipeRef.current = {
      url: null,
      startX: 0,
      initialOffset: 0,
      currentOffset: 0,
    };
  };

  const handleRecentTap = (url: string) => {
    'background only';
    if (openRecentUrl === url) {
      setOpenRecentUrl(null);
      return;
    }
    if (openRecentUrl !== null) {
      setOpenRecentUrl(null);
    }
    openSchemaWithUrl(url);
  };

  const getRecentOffset = (url: string) => {
    if (activeSwipeUrl === url) {
      return activeSwipeOffset;
    }
    return openRecentUrl === url ? -RECENT_DELETE_ACTION_WIDTH : 0;
  };

  const openSchemaHandler = () => {
    'background only';
    openSchemaWithUrl(inputValue);
  };

  const openShowcasePage = () => {
    'background only';
    navigateTo('showcase/menu/main.lynx.bundle', {
      title: 'Showcase',
      title_color: resolved === 'dark' ? 'FFFFFF' : '000000',
      bar_color: resolved === 'dark' ? '181D25' : 'F0F2F5',
      back_button_style: resolved,
    });
  };

  const handleInput = (event: InputEvent) => {
    'background only';
    const currentValue = event.detail.value;
    if (inputError) {
      setInputError('');
    }
    setInputValue(currentValue);
  };

  const handlePaste = () => {
    'background only';
    const clipboardText = getExplorerModule()?.readClipboardText?.();
    if (clipboardText && clipboardText.trim().length > 0) {
      setInputError('');
      setInputValue(clipboardText.trim());
    }
  };

  const getIcon = (name: keyof typeof icons) => icons[name][resolved];
  const getTextColor = () => (resolved === 'dark' ? '#FFFFFF' : '#000000');
  const getPlaceholderColor = () =>
    resolved === 'dark' ? '#FFFFFF80' : '#00000059';

  if (!props.showPage) {
    return <></>;
  }

  const navigatorHeight = 48 + safeArea.bottom;

  return (
    <view
      clip-radius="true"
      className={withTheme('page')}
      style={{ height: `calc(100% - ${navigatorHeight}px)` }}
    >
      <view
        className="page-header"
        style={{ marginTop: `${safeArea.top + 8}px` }}
      >
        <image src={getIcon('Explorer')} className="logo" mode="aspectFit" />
        <text className={withTheme('home-title')}>Lynx Explorer</text>
        <view className="scan">
          {(() => {
            if (SystemInfo.platform !== 'iOS') {
              return <></>;
            }
            return (
              <image
                src={getIcon('Scan')}
                className="scan-icon"
                bindtap={openScan}
                accessibility-element={true}
                accessibility-label="Open Scan"
                accessibility-traits="button"
              />
            );
          })()}
        </view>
      </view>

      <view
        className={withTheme('input-card-url')}
        style={{
          height:
            lynx.__globalProps.platform === 'macos' ||
            lynx.__globalProps.platform === 'windows'
              ? '42%'
              : '30%',
        }}
      >
        <view className="input-header">
          <text className={withTheme('bold-text')}>Bundle URL</text>
          <view
            className={withTheme('secondary-button')}
            bindtap={handlePaste}
            accessibility-element={true}
            accessibility-label="Paste Bundle URL"
            accessibility-traits="button"
          >
            <text className={withTheme('secondary-button-text')}>Paste</text>
          </view>
        </view>
        <view className={withTheme('input-box')}>
          <explorer-input
            className="input-control"
            value={inputValue}
            bindinput={handleInput}
            placeholder="Enter Bundle URL"
            text-color={getTextColor()}
            placeholder-color={getPlaceholderColor()}
          />
          {inputValue ? (
            <view
              className={withTheme('inline-clear')}
              bindtap={clearInput}
              accessibility-element={true}
              accessibility-label="Clear Bundle URL"
              accessibility-traits="button"
            >
              <text className={withTheme('inline-clear-text')}>Clear</text>
            </view>
          ) : (
            <></>
          )}
        </view>
        {inputError ? (
          <text className={withTheme('input-error')}>{inputError}</text>
        ) : (
          <></>
        )}
        <view
          className={withTheme('connect-button')}
          bindtap={openSchemaHandler}
          accessibility-element={true}
          accessibility-label="Open Schema"
          accessibility-traits="button"
        >
          <text
            style="line-height: 22px; color: #ffffff; font-size: 16px"
            accessibility-element={false}
          >
            Go
          </text>
        </view>
      </view>

      {recentSchemas.length > 0 ? (
        <view className={withTheme('recent-card')}>
          <view className="recent-header">
            <text className={withTheme('sub-title')}>Recent</text>
            <view
              className={withTheme('recent-clear')}
              bindtap={clearRecentSchemas}
              accessibility-element={true}
              accessibility-label="Clear Recent URLs"
              accessibility-traits="button"
            >
              <text className={withTheme('recent-clear-text')}>Clear all</text>
            </view>
          </view>
          {recentSchemas.map((url) => {
            const displayText = getRecentDisplayText(url);
            return (
              <view key={url} className="recent-item-shell">
                <view
                  className={withTheme('recent-delete-action')}
                  bindtap={() => removeRecentSchema(url)}
                  accessibility-element={true}
                  accessibility-label={`Remove Recent URL ${url}`}
                  accessibility-traits="button"
                >
                  <text className={withTheme('recent-delete-action-text')}>Delete</text>
                </view>
                <view
                  className={withTheme('recent-item')}
                  bindtap={() => handleRecentTap(url)}
                  bindtouchstart={(event) => handleRecentTouchStart(url, event)}
                  bindtouchmove={(event) => handleRecentTouchMove(url, event)}
                  bindtouchend={() => finalizeRecentSwipe(url)}
                  bindtouchcancel={() => finalizeRecentSwipe(url)}
                  style={{ transform: `translateX(${getRecentOffset(url)}px)` }}
                  accessibility-element={true}
                  accessibility-label={`Open Recent URL ${url}`}
                  accessibility-traits="button"
                >
                  <view className="recent-copy">
                    <text className={withTheme('recent-title')}>
                      {displayText.primaryText}
                    </text>
                    {displayText.secondaryText ? (
                      <text className={withTheme('recent-subtitle')}>
                        {displayText.secondaryText}
                      </text>
                    ) : (
                      <></>
                    )}
                  </view>
                  <view className={withTheme('recent-forward-chip')}>
                    <image src={getIcon('Forward')} className="forward-icon" />
                  </view>
                </view>
              </view>
            );
          })}
        </view>
      ) : (
        <></>
      )}

      <view
        className={withTheme('showcase')}
        bindtap={openShowcasePage}
        accessibility-element={true}
        accessibility-label="Open Show Cases"
        accessibility-traits="button"
      >
        <image src={ShowcaseIcon} className="showcase-icon" />
        <text className={withTheme('text')} accessibility-element={false}>
          Showcase
        </text>
        <view style="margin: auto 5% auto auto; justify-content: center">
          <image src={getIcon('Forward')} className="forward-icon" />
        </view>
      </view>
    </view>
  );
}
