# Function-splitting patterns for the complexity gate

Companion reference for the `rca-component-structuring` skill. Every pattern here exists to hold a
function under 10 logical lines, 3 parameters and 3 exit points, and a file under 120 logical lines,
10 functions, 6 closures and 15 of the two combined.

## Activation gating in the view-model hook

Keep the disabled check out of the JSX. A small factory returns the handler already gated, so the
render function has nothing to branch on and the hook stays flat.

```ts
function makeActivate(disabled: boolean, onActivate?: () => void): () => void {
  return (): void => {
    if (disabled) return;
    onActivate?.();
  };
}

export function useAddButton(props: UiAddButtonProps): AddButtonModel {
  useDevWarning(addButtonWarning(props));
  const interactive: boolean = props.onActivate != null;
  const disabled: boolean = props.disabled ?? false;
  return {
    interactive,
    ariaDisabled: interactive && disabled ? true : undefined,
    label: props.label ?? DEFAULT_LABEL,
    onActivate: makeActivate(disabled, props.onActivate),
  };
}
```

When a factory would need a fourth parameter, take one options object instead of adding arguments.

## Style helpers

A single `sx` builder that spells out every pseudo-state overruns both the line count and the
Halstead volume. Extract the repeated state chrome into its own builder and call it per state.

```ts
function interactiveChromeSx(shadow: string, theme: Theme) {
  return { boxShadow: shadow, border: `1px solid ${theme.palette.grey400}` };
}

export function componentSx(theme: Theme) {
  return {
    backgroundColor: theme.palette.white.main,
    border: `1px solid ${theme.palette.grey300}`,
    '&:hover': interactiveChromeSx(SHADOW_HOVER, theme),
    '&:active': interactiveChromeSx(SHADOW_ACTIVE, theme),
  };
}
```

Name the helpers consistently across components so the next reader recognises the shape.

## Glyph and content files

Put the SVG path constant and its wrapper component in their own file, and the shared label plus
glyph tree in a second one. Both render paths import the same content component, so the wired and
static branches cannot drift apart visually, and neither file pushes `index.tsx` toward the per-file
ceiling.

```ts
const PLUS_PATH = 'M10 2v16M2 10h16';

export function PlusGlyph(): React.ReactElement {
  return <Glyph viewBox="0 0 20 20" path={PLUS_PATH} />;
}
```

## Halstead extraction for a mature component

Halstead volume counts distinct and total operators and operands, so a body that merges props,
normalises slots and renders can cross the per-function ceiling of 1000 long before it looks large.
Move the computation into a named helper that returns the finished value; the render body then holds
only the call.

```ts
function inputSlotProps(props: UiInputProps) {
  const { InputProps, slotProps } = props;
  if (!InputProps) return slotProps;
  return {
    ...slotProps,
    input: (ownerState: unknown) => {
      const base =
        typeof slotProps?.input === 'function' ? slotProps.input(ownerState) : slotProps?.input;
      return { ...base, ...InputProps };
    },
  };
}
```

### The load-bearing destructure

A destructure that strips props out of the rest spread is often doing real work — keeping a
descriptor off the DOM, or stopping a library applying the same props a second time. Removing it
because the bindings "look unused" changes behaviour, and leaving it while reading nothing trips the
unused-variable rule. Keep the destructure and make the body genuinely read the bindings, by passing
them to the helper or to a warnings hook.

```ts
const UiInput = React.forwardRef<HTMLInputElement, UiInputProps>((props, ref) => {
  const { InputProps, slotProps, ...rest } = props;
  useInputAccessibilityWarnings({ InputProps, slotProps });
  return <TextField ref={ref} slotProps={inputSlotProps(props)} {...rest} />;
});
```

## Order of work

1. Read an already-passing component of the same kind and copy its file set — at minimum its
   `index.tsx`, `styles.ts` and view-model hook.
2. Write the hook and the styles first; they absorb most of the logic.
3. Keep each render function to a return statement plus at most a couple of bindings.
4. Run the metrics gate before opening a review, and split further rather than relaxing a limit.
