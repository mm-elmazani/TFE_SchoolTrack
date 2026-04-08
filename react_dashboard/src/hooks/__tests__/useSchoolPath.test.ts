import { describe, it, expect, vi } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useSchoolPath } from '../useSchoolPath';

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ schoolSlug: 'dev' }) };
});

describe('useSchoolPath', () => {
  it('prepends school slug to path', () => {
    const { result } = renderHook(() => useSchoolPath());
    expect(result.current('/students')).toBe('/dev/students');
  });

  it('handles root path', () => {
    const { result } = renderHook(() => useSchoolPath());
    expect(result.current('/')).toBe('/dev/');
  });
});
