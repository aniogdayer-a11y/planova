import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { prepareAvatar } from './avatar.mjs';

test('avatar photos are decoded, cropped, resized and stripped of metadata',async()=>{
  const image=await sharp({create:{width:48,height:32,channels:3,background:'#a68b65'}}).png().withMetadata().toBuffer();
  const avatar=await prepareAvatar(image.toString('base64'));
  assert.ok(avatar.startsWith('data:image/jpeg;base64,'));
  const metadata=await sharp(Buffer.from(avatar.split(',')[1],'base64')).metadata();
  assert.equal(metadata.width,256);assert.equal(metadata.height,256);
  assert.equal(metadata.format,'jpeg');assert.equal(metadata.exif,undefined);assert.equal(metadata.icc,undefined);
  assert.equal(await prepareAvatar(null),'');
});
test('invalid, external, active and oversized avatar inputs are rejected',async()=>{
  for(const value of [undefined,'https://example.test/photo.jpg','invalid!',Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>').toString('base64'),
    Buffer.alloc(2*1024*1024+1).toString('base64')]) {
    await assert.rejects(prepareAvatar(value),error=>error.status===400);
  }
});
