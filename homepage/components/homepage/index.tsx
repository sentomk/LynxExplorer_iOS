// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

import { useEffect, useState } from '@lynx-js/react';
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

export default function HomePage(props: HomePageProps) {
  const { resolved, withTheme } = useTheme();
  const safeArea = useSafeArea();
  const [inputValue, setInputValue] = useState('');
  const [recentSchemas, setRecentSchemas] = useState<string[]>(
    () => readRecentSchemas()
  );

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
      return;
    }

    if (HTTP_SCHEMA_PATTERN.test(normalizedUrl)) {
      setRecentSchemas((prev) => {
        const next = [normalizedUrl, ...prev.filter((item) => item !== normalizedUrl)];
        return next.slice(0, MAX_RECENT_SCHEMAS);
      });
    }
    setInputValue(normalizedUrl);
    openSchema(normalizedUrl);
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
    setInputValue(currentValue);
  };

  const handlePaste = () => {
    'background only';
    const clipboardText = getExplorerModule()?.readClipboardText?.();
    if (clipboardText && clipboardText.trim().length > 0) {
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
        <explorer-input
          className={withTheme('input-box')}
          value={inputValue}
          bindinput={handleInput}
          placeholder="Enter Bundle URL"
          text-color={getTextColor()}
          placeholder-color={getPlaceholderColor()}
        />
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
          </view>
          {recentSchemas.map((url) => {
            return (
              <view
                key={url}
                className="recent-item"
                bindtap={() => openSchemaWithUrl(url)}
                accessibility-element={true}
                accessibility-label={`Open Recent URL ${url}`}
                accessibility-traits="button"
              >
                <text className={withTheme('recent-url')}>{url}</text>
                <image src={getIcon('Forward')} className="forward-icon" />
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
