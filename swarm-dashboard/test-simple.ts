import { createCliRenderer, Text } from '@opentui/core';

async function main() {
  console.error('Creating renderer...');
  
  const renderer = await createCliRenderer({
    useMouse: false,
    enableMouseMovement: false,
  });
  console.error('Renderer created!');
  
  console.error('Adding text...');
  const text = Text({
    content: 'Hello, OpenTUI!',
  });
  renderer.root.add(text);
  console.error('Text added!');
  
  console.error('Starting renderer...');
  renderer.start();
  console.error('Renderer started!');
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
